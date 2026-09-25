"""Binning, weight of evidence (WoE) and information value (IV).

In plain words: every fact about a client is cut into a few groups (bins),
e.g. age 21-29, 30-39, ... Each group gets a number — its *weight of
evidence* — that says whether the group has fewer defaults than average
(positive) or more (negative). The *information value* sums this up into one
number per fact: how much the fact tells us about default.

Rules used here (standard scorecard practice):
  - numeric facts start from up to 10 equal-sized groups (quantiles);
  - neighbouring groups are merged until the default rate moves in one
    direction only (monotonic), so points never zig-zag — "more late
    payments, fewer points", always;
  - groups smaller than 5% of clients are merged into a neighbour;
  - a missing value ("no history") keeps its own group;
  - text facts (e.g. education) keep one group per value; a value held by
    fewer than 5% of clients joins the group whose default rate is closest
    (a tiny group would otherwise get extreme, unreliable points).

WoE = ln(share of all good clients in the group / share of all bad clients
in the group), computed with +0.5 added to counts so that a group with no
defaults does not produce infinity.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

MAX_BINS = 10
MIN_BIN_SHARE = 0.05
MISSING = "Missing"
OTHER = "Other"


@dataclass
class Binning:
    """How one feature is cut into groups, and the WoE of each group."""
    feature: str
    kind: str                                   # "numeric" or "categorical"
    edges: list[float] = field(default_factory=list)       # numeric: inner cut points
    categories: dict[str, str] = field(default_factory=dict)  # categorical: value -> group
    woe: dict[str, float] = field(default_factory=dict)       # group label -> WoE
    iv: float = 0.0
    table: pd.DataFrame | None = None           # per-group counts, bad rate, WoE

    # ---- applying the binning -------------------------------------------
    def labels(self, x: pd.Series) -> pd.Series:
        """Group label of every value."""
        if self.kind == "numeric":
            bins = [-np.inf, *self.edges, np.inf]
            names = _interval_names(self.edges)
            out = pd.cut(x.astype(float), bins=bins, labels=names, right=False).astype(object)
        else:
            out = x.astype(object).map(lambda v: self.categories.get(v, OTHER) if pd.notna(v) else None)
        return out.where(x.notna(), MISSING)

    def transform(self, x: pd.Series) -> pd.Series:
        """WoE of every value (a group never seen in training gets 0 = neutral)."""
        return self.labels(x).map(self.woe).fillna(0.0).astype(float)

    def to_dict(self) -> dict:
        return {"feature": self.feature, "kind": self.kind, "edges": self.edges,
                "categories": self.categories, "woe": self.woe, "iv": self.iv}


# ---------------------------------------------------------------------------
def _interval_names(edges: list[float]) -> list[str]:
    if not edges:
        return ["All"]
    for digits in range(4, 12):          # more precision until every cut point reads differently

        def fmt(v: float) -> str:
            return f"{v:,.{digits - 4}f}" if abs(v) >= 1000 else f"{v:.{digits}g}"

        cuts = [fmt(e) for e in edges]
        if len(set(cuts)) == len(cuts):
            break
    names = [f"< {cuts[0]}"]
    names += [f"{a} to < {b}" for a, b in zip(cuts[:-1], cuts[1:])]
    names.append(f">= {cuts[-1]}")
    return names


def _woe_table(labels: pd.Series, y: pd.Series, order: list[str]) -> pd.DataFrame:
    t = pd.DataFrame({"label": labels.values, "bad": y.values})
    t = t.groupby("label", sort=False).agg(clients=("bad", "size"), bad=("bad", "sum"))
    t = t.reindex([o for o in order if o in t.index])
    t["good"] = t.clients - t.bad
    good_total, bad_total = t.good.sum(), t.bad.sum()
    dist_good = (t.good + 0.5) / (good_total + 0.5 * len(t))
    dist_bad = (t.bad + 0.5) / (bad_total + 0.5 * len(t))
    t["share"] = t.clients / t.clients.sum()
    t["bad_rate"] = t.bad / t.clients
    t["woe"] = np.log(dist_good / dist_bad)
    t["iv_part"] = (dist_good - dist_bad) * t.woe
    return t


def _merge_numeric(x: pd.Series, y: pd.Series, min_count: float) -> list[float]:
    """Quantile start, then merge until monotonic and every group has >= min_count clients."""
    # Edges are actual data values ("lower" quantiles) above the minimum, so every
    # group [edge_i, edge_i+1) contains at least the value edge_i: no empty groups.
    qs = np.unique(np.quantile(x, np.linspace(0, 1, MAX_BINS + 1)[1:-1], method="lower"))
    edges = [float(e) for e in qs if e > x.min()]
    values, target = x.to_numpy(), y.to_numpy()

    while edges:
        idx = np.searchsorted(np.array(edges), values, side="right")   # same rule as pd.cut(right=False)
        g = pd.DataFrame({"b": idx, "y": target}).groupby("b")["y"].agg(["size", "mean"])
        rates, sizes = g["mean"].to_numpy(), g["size"].to_numpy()
        # 1. merge the smallest group if below the minimum share
        small = np.argmin(sizes)
        if sizes[small] < min_count:
            if small == 0:
                drop = 0
            elif small == len(sizes) - 1:
                drop = small - 1
            else:   # merge with the neighbour whose default rate is closer
                left, right = abs(rates[small] - rates[small - 1]), abs(rates[small] - rates[small + 1])
                drop = small - 1 if left <= right else small
            edges.pop(drop)
            continue
        # 3. merge the pair that breaks the overall direction the most
        # 2. with two groups there is no direction to break: done
        if len(rates) <= 2 or np.std(rates) == 0:
            break
        direction = np.sign(np.corrcoef(np.arange(len(rates)), rates)[0, 1])
        diffs = np.diff(rates) * direction
        if (diffs < 0).any():
            edges.pop(int(np.argmin(diffs)))
            continue
        break
    return edges


def _group_categories(x: pd.Series, y: pd.Series, min_count: float) -> dict[str, str]:
    """Values held by fewer than min_count clients join the large value whose default
    rate is closest (a tiny group would otherwise get extreme, unreliable points)."""
    stats = y.groupby(x).agg(["size", "mean"])
    large = stats[stats["size"] >= min_count]
    if large.empty:                                  # nothing large enough: keep the biggest
        large = stats.nlargest(1, "size")
    target = {v: v for v in large.index}
    for v, row in stats.drop(large.index).iterrows():
        target[v] = (large["mean"] - row["mean"]).abs().idxmin()
    members = {}
    for v, t in target.items():
        members.setdefault(t, []).append(v)
    label = {t: t if len(m) == 1 else f"{t} (+ {', '.join(sorted(x for x in m if x != t))})"
             for t, m in members.items()}
    return {v: label[t] for v, t in target.items()}


def fit_binning(x: pd.Series, y: pd.Series, feature: str) -> Binning:
    """Learn the groups and their WoE from training data."""
    present = x.notna()
    if pd.api.types.is_numeric_dtype(x):
        # the 5% minimum is a share of ALL clients, including those with a missing value
        edges = (_merge_numeric(x[present].astype(float), y[present], MIN_BIN_SHARE * len(x))
                 if present.any() else [])
        b = Binning(feature, "numeric", edges=edges)
        order = _interval_names(edges) + [MISSING]
    else:
        cats = _group_categories(x[present].astype(str), y[present], MIN_BIN_SHARE * len(x))
        b = Binning(feature, "categorical", categories=cats)
        rate = y[present].groupby(x[present].astype(str).map(cats)).mean()
        order = list(rate.sort_values().index) + [OTHER, MISSING]     # safest group first
    labels = b.labels(x)
    table = _woe_table(labels, y, order)
    b.woe = {str(k): float(v) for k, v in table.woe.items()}
    b.iv = float(table.iv_part.sum())
    b.table = table
    return b
