#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from string import Template
from typing import Iterable, List, Optional, Sequence


MODES = ("map-reduce", "extract-synthesize", "question-led")
DEFAULT_PROMPTS_DIR = Path(__file__).resolve().parent / "prompts" / "codex_summarize_pipeline"


@dataclass(frozen=True)
class CodexConfig:
    model: Optional[str]
    oss: bool
    local_provider: Optional[str]
    extra_args: Sequence[str]


@dataclass(frozen=True)
class PromptSet:
    chunk_map: str
    chunk_extract: str
    chunk_question: str
    reduce: str
    merge_json: str
    synthesize: str


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def split_into_paragraphs(text: str) -> List[str]:
    parts = re.split(r"\n\s*\n+", text.strip())
    return [p.strip() for p in parts if p.strip()]


def chunk_paragraphs(paragraphs: Sequence[str], max_chars: int) -> List[str]:
    chunks: List[str] = []
    current: List[str] = []
    current_len = 0

    def flush() -> None:
        nonlocal current, current_len
        if current:
            chunks.append("\n\n".join(current).strip())
            current = []
            current_len = 0

    for p in paragraphs:
        if len(p) > max_chars:
            flush()
            for i in range(0, len(p), max_chars):
                chunks.append(p[i : i + max_chars].strip())
            continue

        additional = len(p) + (2 if current else 0)
        if current_len + additional <= max_chars:
            current.append(p)
            current_len += additional
        else:
            flush()
            current.append(p)
            current_len = len(p)

    flush()
    return [c for c in chunks if c.strip()]


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _escape_template_value(value: str) -> str:
    return value.replace("$", "$$")


def render_template(template_text: str, **values: str) -> str:
    safe = {k: _escape_template_value(v) for k, v in values.items()}
    return Template(template_text).substitute(**safe)


def load_prompts(prompts_dir: Path) -> PromptSet:
    def load(name: str) -> str:
        p = prompts_dir / name
        if not p.exists():
            raise FileNotFoundError(f"Missing prompt template: {p}")
        return p.read_text(encoding="utf-8")

    return PromptSet(
        chunk_map=load("chunk_map.md.tmpl"),
        chunk_extract=load("chunk_extract.json.tmpl"),
        chunk_question=load("chunk_question.md.tmpl"),
        reduce=load("reduce.md.tmpl"),
        merge_json=load("merge_json.tmpl"),
        synthesize=load("synthesize.md.tmpl"),
    )


def run_codex(prompt: str, output_last_message: Path, codex: CodexConfig, log_path: Path) -> None:
    ensure_dir(output_last_message.parent)
    ensure_dir(log_path.parent)

    cmd: List[str] = [
        "codex",
        "--sandbox",
        "read-only",
        "--ask-for-approval",
        "never",
    ]

    if codex.model:
        cmd += ["--model", codex.model]
    if codex.oss:
        cmd += ["--oss"]
    if codex.local_provider:
        cmd += ["--local-provider", codex.local_provider]

    cmd += [
        "exec",
        "--skip-git-repo-check",
        "--color",
        "never",
        "--output-last-message",
        str(output_last_message),
        "-",
    ]
    cmd += list(codex.extra_args)

    with log_path.open("wb") as logf:
        proc = subprocess.run(
            cmd,
            input=prompt.encode("utf-8", errors="replace"),
            stdout=logf,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if proc.returncode != 0:
        raise RuntimeError(f"codex exec failed (exit {proc.returncode}); see {log_path}")


def load_text_files(paths: Iterable[Path]) -> List[str]:
    return [read_text(p).strip() for p in paths]


def batched(items: Sequence[str], max_chars: int) -> List[List[str]]:
    batches: List[List[str]] = []
    current: List[str] = []
    current_len = 0
    for s in items:
        s_len = len(s) + 2
        if current and (current_len + s_len) > max_chars:
            batches.append(current)
            current = []
            current_len = 0
        current.append(s)
        current_len += s_len
    if current:
        batches.append(current)
    return batches


def reduce_hierarchical(
    summaries: Sequence[str],
    *,
    codex: CodexConfig,
    out_dir: Path,
    final_max_words: int,
    prompts: PromptSet,
    max_batch_chars: int = 70_000,
) -> str:
    level = 0
    current = list(summaries)

    while len(current) > 1:
        level += 1
        batches = batched(current, max_batch_chars)
        next_level: List[str] = []

        for bi, batch in enumerate(batches, start=1):
            prompt = render_template(prompts.reduce, final_max_words=str(final_max_words))
            for i, s in enumerate(batch, start=1):
                prompt += f"--- summary {i} ---\n{s}\n\n"

            out = out_dir / f"reduce_level{level:02d}_batch{bi:02d}.md"
            log = out_dir / "logs" / f"reduce_level{level:02d}_batch{bi:02d}.log"
            run_codex(prompt, out, codex, log)
            next_level.append(read_text(out).strip())

        current = next_level

    return current[0].strip()


def prompt_for_mode(
    mode: str,
    *,
    prompts: PromptSet,
    chunk_index: int,
    chunk_count: int,
    chunk_text: str,
    goal: str,
) -> str:
    values = {
        "chunk_index": str(chunk_index),
        "chunk_count": str(chunk_count),
        "chunk_text": chunk_text,
        "goal": goal,
    }

    if mode == "map-reduce":
        return render_template(prompts.chunk_map, **values)
    if mode == "extract-synthesize":
        return render_template(prompts.chunk_extract, **values)
    if mode == "question-led":
        return render_template(prompts.chunk_question, **values)
    raise ValueError(f"Unknown mode: {mode}")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Codex-only multi-step summarization pipeline (no direct API calls).")
    p.add_argument("--input", required=True, help="Path to article text/markdown file.")
    p.add_argument("--mode", choices=MODES, default="map-reduce")
    p.add_argument("--out-dir", default="", help="Output directory (default: .codex-pipeline/<name>-<timestamp>/).")
    p.add_argument("--chunk-chars", type=int, default=12_000, help="Max characters per chunk.")
    p.add_argument("--final-max-words", type=int, default=180, help="Hard cap for final output length.")
    p.add_argument("--goal", default="Executive summary for a busy reader.", help="Used for question-led mode.")
    p.add_argument(
        "--prompts-dir",
        default=str(DEFAULT_PROMPTS_DIR),
        help=f"Directory containing prompt templates (default: {DEFAULT_PROMPTS_DIR}).",
    )

    p.add_argument("--model", default=None, help="Optional Codex model override.")
    p.add_argument("--oss", action="store_true", help="Use local open-source provider (requires local server).")
    p.add_argument("--local-provider", default=None, choices=("lmstudio", "ollama"), help="Local provider.")
    p.add_argument("--codex-arg", action="append", default=[], help="Extra args passed to `codex` (repeatable).")

    p.add_argument("--print-intermediate", action="store_true", help="Also print intermediate outputs to stdout.")
    p.add_argument("--dry-run", action="store_true", help="Only write chunks; do not call `codex`.")
    return p.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        raise SystemExit(f"Input not found: {input_path}")

    timestamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    safe_name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", input_path.stem)[:60] or "article"
    out_dir = Path(args.out_dir).expanduser() if args.out_dir else Path(".codex-pipeline") / f"{safe_name}-{timestamp}"
    out_dir = out_dir.resolve()
    ensure_dir(out_dir)

    codex = CodexConfig(
        model=args.model,
        oss=bool(args.oss),
        local_provider=args.local_provider,
        extra_args=tuple(args.codex_arg),
    )
    prompts = load_prompts(Path(args.prompts_dir).expanduser().resolve())

    text = read_text(input_path)
    paragraphs = split_into_paragraphs(text)
    chunks = chunk_paragraphs(paragraphs, max_chars=args.chunk_chars)
    if not chunks:
        raise SystemExit("No content found after chunking.")

    eprint(f"[codex-pipeline] mode={args.mode} chunks={len(chunks)} out={out_dir}")

    chunks_dir = out_dir / "chunks"
    maps_dir = out_dir / "maps"
    ensure_dir(chunks_dir)
    ensure_dir(maps_dir)

    if args.dry_run:
        for i, chunk in enumerate(chunks, start=1):
            (chunks_dir / f"{i:04d}.txt").write_text(chunk, encoding="utf-8")
        eprint(f"[codex-pipeline] dry-run wrote {len(chunks)} chunks to {chunks_dir}")
        return 0

    for i, chunk in enumerate(chunks, start=1):
        (chunks_dir / f"{i:04d}.txt").write_text(chunk, encoding="utf-8")

        prompt = prompt_for_mode(
            args.mode,
            prompts=prompts,
            chunk_index=i,
            chunk_count=len(chunks),
            chunk_text=chunk,
            goal=args.goal,
        )
        out_path = maps_dir / (f"{i:04d}.json" if args.mode == "extract-synthesize" else f"{i:04d}.md")
        log_path = out_dir / "logs" / f"map_{i:04d}.log"

        eprint(f"[codex-pipeline] map {i}/{len(chunks)} -> {out_path.name}")
        run_codex(prompt, out_path, codex, log_path)

        if args.print_intermediate:
            sys.stdout.write(read_text(out_path).rstrip() + "\n\n")

    if args.mode in ("map-reduce", "question-led"):
        summaries = load_text_files(sorted(maps_dir.glob("*.md")))
        final = reduce_hierarchical(
            summaries,
            codex=codex,
            out_dir=out_dir / "reduce",
            final_max_words=args.final_max_words,
            prompts=prompts,
        )
        final_path = out_dir / "final_summary.md"
        final_path.write_text(final + "\n", encoding="utf-8")
        print(final)
        eprint(f"[codex-pipeline] wrote {final_path}")
        return 0

    if args.mode == "extract-synthesize":
        json_fragments = load_text_files(sorted(maps_dir.glob("*.json")))
        prompt = prompts.merge_json
        for i, frag in enumerate(json_fragments, start=1):
            prompt += f"--- fragment {i} ---\n{frag}\n\n"

        merged_json_path = out_dir / "merged_facts.json"
        merged_log = out_dir / "logs" / "merge_json.log"
        eprint("[codex-pipeline] merge JSON")
        run_codex(prompt, merged_json_path, codex, merged_log)

        merged_text = read_text(merged_json_path).strip()
        try:
            merged = json.loads(merged_text)
        except json.JSONDecodeError:
            merged = {"_raw": merged_text}

        synth_prompt = render_template(
            prompts.synthesize,
            final_max_words=str(args.final_max_words),
            fact_record=json.dumps(merged, ensure_ascii=False),
        )
        final_path = out_dir / "final_summary.md"
        final_log = out_dir / "logs" / "final_summarize.log"
        eprint("[codex-pipeline] synthesize final summary")
        run_codex(synth_prompt, final_path, codex, final_log)

        final = read_text(final_path).strip()
        print(final)
        eprint(f"[codex-pipeline] wrote {final_path}")
        return 0

    raise SystemExit(f"Unhandled mode: {args.mode}")


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        eprint("\n[codex-pipeline] interrupted")
        raise SystemExit(130)

