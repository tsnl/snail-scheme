"""Duration charts shared by the native comparison and the R7RS suite."""

import statistics
import textwrap

# ---- Sorted time comparisons ----


ORANGE = "#ec741c"
INK = "#253341"
GRAY = "#8997a6"


def duration_chart(series, destination, *, title, subtitle, notes, missing=()):
    """Each series has a label, checked seconds, and a color; missing is text only."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    with plt.rc_context(
        {
            "font.family": "DejaVu Sans",
            "svg.fonttype": "none",
            "svg.hashsalt": "snail-duration",
            "text.color": INK,
        }
    ):
        series = sorted(series, key=lambda row: statistics.median(row["seconds"]), reverse=True)
        footer = (
            list(notes) + textwrap.wrap("No timing — " + "; ".join(missing), 112)
            if missing
            else list(notes)
        )
        fig, axis = plt.subplots(figsize=(9.6, 4.3 + 0.18 * max(0, len(footer) - 2)))
        fig.subplots_adjust(left=0.09, right=0.98, bottom=0.19 + len(footer) * 0.033, top=0.70)
        draw_bars(axis, series)
        fig.text(0.09, 0.92, title, fontsize=19, weight="bold")
        fig.text(0.09, 0.85, subtitle, fontsize=11, color="#526170")
        fig.text(0.09, 0.035, "\n".join(footer), fontsize=9, linespacing=1.6, color="#526170")
        save_chart(fig, destination)
        plt.close(fig)


def draw_bars(axis, series):
    if not series:
        axis.set_axis_off()
        axis.text(0.5, 0.5, "No successful timing", ha="center", transform=axis.transAxes)
        return
    largest = max(max(row["seconds"]) for row in series)
    scale, unit = (1, "Seconds") if largest >= 1 else (1000, "Milliseconds")
    if largest < 0.001:
        scale, unit = 1_000_000, "Microseconds"
    for index, row in enumerate(series):
        draw_bar(axis, index, row, scale)
    style_axis(axis, series, largest * scale, unit)


def draw_bar(axis, index, row, scale):
    samples = [value * scale for value in row["seconds"]]
    median = statistics.median(samples)
    axis.bar(index, median, width=0.58, color=row["color"], zorder=3)
    if len(samples) > 1:
        axis.errorbar(
            index,
            median,
            yerr=[[median - min(samples)], [max(samples) - median]],
            fmt="none",
            ecolor=INK,
            elinewidth=1,
            capsize=3,
            zorder=4,
        )
    axis.annotate(
        f"{median:.3g}",
        (index, max(samples)),
        xytext=(0, 7),
        textcoords="offset points",
        ha="center",
        fontsize=12,
        weight="bold",
        color=INK,
    )


def style_axis(axis, series, maximum, unit):
    axis.set(
        xticks=range(len(series)),
        xticklabels=[row["label"] for row in series],
        ylim=(0, maximum * 1.22),
        xlim=(-0.65, len(series) - 0.35),
    )
    axis.set_title(f"{unit} · lower is faster", loc="left", fontsize=10, color="#526170", pad=12)
    axis.set_axisbelow(True)
    axis.grid(axis="y", color="#e9edf0", linewidth=0.8)
    axis.spines[["top", "right", "left"]].set_visible(False)
    axis.spines["bottom"].set_color("#d6dde3")
    axis.tick_params(axis="both", length=0, labelcolor=INK, labelsize=10, pad=9)
    for tick, row in zip(axis.get_xticklabels(), series):
        if row["color"] != GRAY:
            tick.set_color("#b95309")
            tick.set_weight("bold")


def save_chart(fig, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    for extension in ["svg", "png"]:
        fig.savefig(
            destination.with_suffix("." + extension),
            dpi=180,
            metadata={"Date": None} if extension == "svg" else {},
        )
