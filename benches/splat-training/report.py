"""The bench's tables, from what `train` and `score` kept:

    python3 report.py build/benches/splat-training

The first gives, for each run: its trainer; the seconds its training loop
took, by the trainer's own clock, without loading or evaluating; the
gaussians it ended with; the most GPU memory in use while it trained,
beyond what was in use before it started; the held-out PSNR, SSIM and
LPIPS that `score` gave it; and the PSNR the trainer reported itself, where
it reports one.

The second gives each run's seconds and gaussians at step 7,000, the step
the paper reports first, where every trainer reports them too, and where
the train app's cloud has not yet reached its cap.
"""

import json
import os
import re
import sys

EARLY = 7000

# ---- Each trainer's own reports ----

# Each answers the seconds and the gaussians at the steps it reports among
# EARLY and the last, and the PSNR it reported itself, or None.


def read(run, name):
    with open(os.path.join(run, name), errors="replace") as f:
        return f.read()


def ours(run, steps):
    """The train app reports the seconds since training began and the
    gaussians every hundredth step, and the held-out PSNR at the end."""
    log = read(run, "log")
    pattern = r"^step (\d+) loss \S+ gaussians (\d+)/\d+ .*seconds (\S+)$"
    reports = {int(step): (float(seconds), int(gaussians))
               for step, gaussians, seconds in re.findall(pattern, log, re.M)}
    own = re.search(r"^held-out PSNR (\S+)$", log, re.M)
    return reports, own and float(own.group(1))


def gsplat(run, steps):
    """gsplat keeps the seconds since its loop began and the gaussians with
    each checkpoint, at step 7,000 and the last, and its evaluation's
    scores beside the last, each named by the step counted from 0, in at
    least four digits."""
    stats = os.path.join(run, "stats")
    reports = {}
    for step in (EARLY, steps):
        path = os.path.join(stats, f"train_step{step - 1:04d}_rank0.json")
        if os.path.exists(path):
            with open(path) as f:
                trained = json.load(f)
            reports[step] = trained["ellipse_time"], trained["num_GS"]
    own = None
    if os.path.exists(os.path.join(stats, f"val_step{steps - 1:04d}.json")):
        with open(os.path.join(stats, f"val_step{steps - 1:04d}.json")) as f:
            own = json.load(f)["psnr"]
    return reports, own


def inria(run, steps):
    """The INRIA code's progress bar starts as its loop does and shows the
    seconds since every tenth step, the first time with that step's own;
    the cloud it saves at step 7,000 and the last counts the gaussians in
    its header."""
    log = read(run, "log")
    reports = {}
    for step in (EARLY, steps):
        shown = re.search(rf"\b{step}/{steps} \[([\d:]+)<", log)
        ply = os.path.join(run, "model", "point_cloud", f"iteration_{step}", "point_cloud.ply")
        if shown and os.path.exists(ply):
            seconds = 0
            for part in shown.group(1).split(":"):
                seconds = seconds * 60 + int(part)
            with open(ply, "rb") as f:
                header = f.read(1024).decode("latin-1")
            gaussians = int(re.search(r"element vertex (\d+)", header).group(1))
            reports[step] = float(seconds), gaussians
    return reports, None


TRAINERS = {"ours": ours, "gsplat": gsplat, "inria": inria}

# ---- What every run shares ----


def peak_memory(run):
    """MiB in use at most, less the first sample, taken before the trainer
    started."""
    samples = [int(line.split(",")[0]) for line in read(run, "gpu").splitlines() if line.strip()]
    return max(samples) - samples[0]


def runs(work):
    """Each run's name, trainer, steps, and its reports, or None where it has
    not finished, or failed."""
    for name in sorted(os.listdir(os.path.join(work, "runs"))):
        run = os.path.join(work, "runs", name)
        trainer = read(run, "trainer").strip()
        steps = int(read(run, "steps"))
        try:
            reports, own = TRAINERS[trainer](run, steps)
            memory = peak_memory(run)
        except (OSError, ValueError, KeyError, AttributeError):
            reports, own, memory = {}, None, None
        finished = steps in reports and memory is not None
        yield name, trainer, steps, (reports, own, memory) if finished else None


# ---- The tables ----


def cell(value, form):
    return "" if value is None else format(value, form)


def main(work):
    scores = {}
    if os.path.exists(os.path.join(work, "scores", "results.json")):
        with open(os.path.join(work, "scores", "results.json")) as f:
            scores = json.load(f)
    every = list(runs(work))
    print("| Run | Trainer | Steps | Seconds | Gaussians | Peak MiB | PSNR | SSIM | LPIPS | Own PSNR |")
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for name, trainer, steps, finished in every:
        if finished is None:
            print(f"| {name} | {trainer} | {steps} | not finished | | | | | | |")
            continue
        reports, own, memory = finished
        seconds, gaussians = reports[steps]
        score = scores.get(name, {})
        print(f"| {name} | {trainer} | {steps} | {seconds:.1f} | {gaussians:,} | {memory:,} | "
              f"{cell(score.get('PSNR'), '.3f')} | {cell(score.get('SSIM'), '.4f')} | "
              f"{cell(score.get('LPIPS'), '.4f')} | {cell(own, '.3f')} |")
    print()
    print(f"| Run | Trainer | Seconds to {EARLY:,} | Gaussians at {EARLY:,} |")
    print("| --- | --- | ---: | ---: |")
    for name, trainer, steps, finished in every:
        if finished is not None and EARLY in finished[0]:
            seconds, gaussians = finished[0][EARLY]
            print(f"| {name} | {trainer} | {seconds:.1f} | {gaussians:,} |")


if __name__ == "__main__":
    main(sys.argv[1])
