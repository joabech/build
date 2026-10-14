#!/usr/bin/env python3
# finetune.py -- the whole pipeline in one script, same code on macOS and
# Linux:
#
#   train:  split dataset -> trl.SFTTrainer + peft LoRA/DoRA -> adapter
#   export: merge adapter into base (peft) -> convert_hf_to_gguf.py (f16)
#           -> llama-quantize (e.g. Q5_K_M)
#
# The training device is picked automatically: CUDA if present, else Apple
# Silicon's GPU (MPS), else CPU. Invoked by build/finetune.mk; run it by
# hand with --help for the full option list.
#
# Usage:
#   finetune.py train <profile> --model M (--dataset F | --data DIR) [options]
#   finetune.py export [--adapter-path DIR | --pick N] [options]
#   finetune.py list

import argparse
import json
import os
import pathlib
import random
import shutil
import subprocess
import sys
import time

import yaml

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROFILE_DIR = SCRIPT_DIR / "profiles"
PROFILES = sorted(p.stem for p in PROFILE_DIR.glob("*.yaml"))
WORKSPACE = pathlib.Path(os.environ.get("WORKSPACE") or os.getcwd())
LLAMA_CPP_DIR = pathlib.Path(os.environ.get("LLAMA_CPP_DIR") or WORKSPACE / "llama.cpp")
LLAMA_QUANTIZE_BIN = pathlib.Path(
    os.environ.get("LLAMA_QUANTIZE_BIN") or LLAMA_CPP_DIR / "build/bin/llama-quantize")
ADAPTERS_DIR = WORKSPACE / "adapters"


def die(msg):
    sys.exit(f"error: {msg}")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def pick_device():
    import torch
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def split_dataset(src, out_dir, val_split, seed):
    lines = [l if l.endswith("\n") else l + "\n"
             for l in src.read_text().splitlines(keepends=True) if l.strip()]
    random.Random(seed).shuffle(lines)
    n_val = max(1, int(len(lines) * val_split))
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "valid.jsonl").write_text("".join(lines[:n_val]))
    (out_dir / "train.jsonl").write_text("".join(lines[n_val:]))
    log(f"Split {src} -> {out_dir} (train={len(lines) - n_val} valid={n_val})")


def load_profile(name, overrides):
    cfg = yaml.safe_load((PROFILE_DIR / f"{name}.yaml").read_text())
    peft_cfg, sft_cfg = dict(cfg.get("peft") or {}), dict(cfg.get("sft") or {})
    for ov in overrides:
        path, _, value = ov.partition("=")
        section, _, key = path.partition(".")
        target = {"peft": peft_cfg, "sft": sft_cfg}.get(section)
        if target is None or not key:
            die(f"--override must look like peft.<key>=<v> or sft.<key>=<v>, got {ov!r}")
        target[key] = yaml.safe_load(value)
    # "auto" lets peft pick the model's attention projections itself.
    if peft_cfg.get("target_modules") == "auto":
        peft_cfg["target_modules"] = None
    return peft_cfg, sft_cfg


def cmd_train(args):
    if bool(args.dataset) == bool(args.data):
        die("pass exactly one of --dataset <raw.jsonl> or --data <dir>")
    peft_cfg, sft_cfg = load_profile(args.profile, args.override)
    if args.iters:
        sft_cfg["max_steps"] = args.iters
        sft_cfg.pop("num_train_epochs", None)

    if args.dataset:
        src = pathlib.Path(args.dataset)
        if not src.is_file():
            die(f"dataset file not found: {src}")
        data_dir = WORKSPACE / "data" / src.stem
    else:
        data_dir = pathlib.Path(args.data)
        if not (data_dir / "train.jsonl").is_file():
            die(f"{data_dir}/train.jsonl not found")

    adapter = pathlib.Path(args.adapter_path or
                           ADAPTERS_DIR / f"{args.profile}-{time.strftime('%Y%m%d-%H%M%S')}")
    do_gguf = args.gguf if args.gguf is not None else args.profile != "test"

    log(f"Profile:      {args.profile}  ({PROFILE_DIR / args.profile}.yaml)")
    log(f"Model:        {args.model}")
    log(f"Data dir:     {data_dir}")
    log(f"Adapter path: {adapter}")
    log(f"peft:         {peft_cfg}")
    log(f"sft:          {sft_cfg}")
    log(f"GGUF export:  {'yes, ' + args.quant if do_gguf else 'no'}")
    if do_gguf:
        check_export_tools()
    if args.dry_run:
        return

    if args.dataset:
        split_dataset(src, data_dir, args.val_split, args.seed)
    train(args.model, data_dir, adapter, peft_cfg, sft_cfg, args.seed, args.profile)
    if do_gguf:
        export(adapter, args.model, args.quant, args.keep_intermediates)


def auto_target_modules(model):
    # peft's per-architecture defaults (None = use them) lag behind new
    # models such as qwen3_5; without one, adapt every linear layer.
    from peft.utils.constants import TRANSFORMERS_MODELS_TO_LORA_TARGET_MODULES_MAPPING
    from transformers import AutoConfig
    model_type = AutoConfig.from_pretrained(model).model_type
    return None if model_type in TRANSFORMERS_MODELS_TO_LORA_TARGET_MODULES_MAPPING else "all-linear"


def train(model, data_dir, adapter, peft_cfg, sft_cfg, seed, profile):
    from datasets import load_dataset
    from peft import LoraConfig
    from transformers import AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    device = pick_device()
    log(f"Device:       {device}")
    if device == "cpu" and profile == "high":
        log("WARNING: 'high' on CPU only is a multi-hour-to-multi-day run on real "
            "datasets -- 'medium' is the practical choice without a GPU.")

    files = {"train": str(data_dir / "train.jsonl")}
    if (data_dir / "valid.jsonl").is_file():
        files["validation"] = str(data_dir / "valid.jsonl")
    else:
        for k in ("eval_strategy", "eval_steps"):
            sft_cfg.pop(k, None)
    dataset = load_dataset("json", data_files=files)

    if peft_cfg.get("target_modules") is None:
        peft_cfg["target_modules"] = auto_target_modules(model)
        log(f"LoRA targets: {peft_cfg['target_modules'] or 'peft default for this model'}")

    tokenizer = AutoTokenizer.from_pretrained(model)
    trainer = SFTTrainer(
        model=model,
        args=SFTConfig(
            output_dir=str(adapter),
            seed=seed,
            use_cpu=device == "cpu",
            # bf16 only where it's reliably fast; MPS and CPU train in fp32.
            bf16=device == "cuda" and __import__("torch").cuda.is_bf16_supported(),
            report_to="none",
            **sft_cfg,
        ),
        train_dataset=dataset["train"],
        eval_dataset=dataset.get("validation"),
        processing_class=tokenizer,
        peft_config=LoraConfig(task_type="CAUSAL_LM", **peft_cfg),
    )
    trainer.train()
    trainer.save_model(str(adapter))
    tokenizer.save_pretrained(str(adapter))
    log(f"Adapter saved to {adapter}")


def check_export_tools():
    if not LLAMA_QUANTIZE_BIN.is_file():
        die(f"{LLAMA_QUANTIZE_BIN} not found -- run 'make llama.cpp-build' first")
    if not (LLAMA_CPP_DIR / "convert_hf_to_gguf.py").is_file():
        die(f"{LLAMA_CPP_DIR}/convert_hf_to_gguf.py not found -- is llama.cpp cloned?")


def base_model_of(adapter):
    cfg = json.loads((adapter / "adapter_config.json").read_text())
    return cfg.get("base_model_name_or_path")


def export(adapter, model, quant, keep_intermediates):
    from peft import AutoPeftModelForCausalLM
    from transformers import AutoTokenizer

    name = f"{pathlib.Path(model).name}-{adapter.name}"
    gguf_dir = WORKSPACE / "gguf"
    fused = WORKSPACE / "fused" / adapter.name
    f16 = gguf_dir / f"{name}-f16.gguf"
    final = gguf_dir / f"{name}-{quant.lower()}.gguf"
    gguf_dir.mkdir(parents=True, exist_ok=True)

    log(f"Merging adapter into {model} -> {fused}")
    merged = AutoPeftModelForCausalLM.from_pretrained(str(adapter), dtype="auto")
    merged.merge_and_unload().save_pretrained(str(fused))
    AutoTokenizer.from_pretrained(str(adapter)).save_pretrained(str(fused))

    log("Converting to f16 GGUF...")
    subprocess.run([sys.executable, str(LLAMA_CPP_DIR / "convert_hf_to_gguf.py"),
                    str(fused), "--outfile", str(f16), "--outtype", "f16"], check=True)
    log(f"Quantizing to {quant}...")
    subprocess.run([str(LLAMA_QUANTIZE_BIN), str(f16), str(final), quant], check=True)

    if not keep_intermediates:
        shutil.rmtree(fused)
        f16.unlink()
    log(f"Done: {final} ({final.stat().st_size / 2**20:.0f} MiB)")


def sessions():
    if not ADAPTERS_DIR.is_dir():
        return []
    dirs = [d for d in ADAPTERS_DIR.iterdir() if (d / "adapter_config.json").is_file()]
    return sorted(dirs, key=lambda d: d.stat().st_mtime, reverse=True)


def cmd_list(_args):
    found = sessions()
    if not found:
        die(f"no finished training sessions under {ADAPTERS_DIR}")
    log(f"Finished training sessions in {ADAPTERS_DIR} (newest first):")
    for i, d in enumerate(found, 1):
        log(f"  {i:2d}) {d.name}   [{base_model_of(d)}]")
    return found


def cmd_export(args):
    if args.adapter_path:
        adapter = pathlib.Path(args.adapter_path)
    else:
        found = cmd_list(args)
        pick = args.pick
        if pick is None:
            if not sys.stdin.isatty():
                die("no terminal for interactive selection -- pass ADAPTER=<N>")
            pick = input(f"Select a session number [1-{len(found)}]: ").strip()
        if not str(pick).isdigit() or not 1 <= int(pick) <= len(found):
            die(f"{pick!r} is not a valid session number (1-{len(found)})")
        adapter = found[int(pick) - 1]
    if not (adapter / "adapter_config.json").is_file():
        die(f"{adapter} is not a finished adapter directory (no adapter_config.json)")
    model = args.model or base_model_of(adapter)

    log(f"Adapter:      {adapter}")
    log(f"Model:        {model}")
    log(f"Quant:        {args.quant}")
    check_export_tools()
    if not args.dry_run:
        export(adapter, model, args.quant, args.keep_intermediates)


def main():
    p = argparse.ArgumentParser(description="Fine-tune a chat model and export a quantized GGUF.")
    sub = p.add_subparsers(dest="cmd", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--quant", default=os.environ.get("QUANT") or "Q5_K_M",
                        help="llama-quantize type (default: %(default)s)")
    common.add_argument("--keep-intermediates", action="store_true",
                        help="keep the merged HF model and the f16 GGUF")
    common.add_argument("--dry-run", action="store_true", help="print the plan, run nothing")

    t = sub.add_parser("train", parents=[common], help="train an adapter (and export a GGUF)")
    t.add_argument("profile", choices=PROFILES)
    t.add_argument("--model", required=True, help="local model dir or Hugging Face repo id")
    t.add_argument("--dataset", help="raw chatml-messages .jsonl; gets split into data/<name>/")
    t.add_argument("--data", help="already-split dir with train.jsonl (+ valid.jsonl)")
    t.add_argument("--adapter-path", help="default: adapters/<profile>-<timestamp>")
    t.add_argument("--val-split", type=float, default=float(os.environ.get("VAL_SPLIT") or 0.1))
    t.add_argument("--seed", type=int, default=int(os.environ.get("SEED") or 42))
    t.add_argument("--iters", type=int, help="fixed number of optimizer steps instead of epochs")
    t.add_argument("--gguf", dest="gguf", action="store_true", default=None,
                   help="force GGUF export (default: on, except for 'test')")
    t.add_argument("--no-gguf", dest="gguf", action="store_false")
    t.add_argument("--override", action="append", default=[], metavar="SECTION.KEY=VALUE",
                   help="override a profile value, e.g. sft.learning_rate=3e-5 (repeatable)")
    t.set_defaults(func=cmd_train)

    e = sub.add_parser("export", parents=[common], help="GGUF from an already-trained adapter")
    e.add_argument("--adapter-path", help="adapter dir; default: choose from 'list'")
    e.add_argument("--pick", help="session number from 'list' (non-interactive)")
    e.add_argument("--model", help="base model; default: read from adapter_config.json")
    e.set_defaults(func=cmd_export)

    sub.add_parser("list", help="list finished training sessions").set_defaults(func=cmd_list)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
