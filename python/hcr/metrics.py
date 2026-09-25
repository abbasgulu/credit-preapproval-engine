"""Model quality measures (plain explanations in docs/glossary.md).

  gini  - does the model rank risky clients above safe ones? 0 = coin toss, 1 = perfect
  ks    - the largest gap between the score distributions of good and bad clients
  brier - average squared error of the probability; lower is better
  psi   - do two populations (e.g. training vs new applicants) look alike? < 0.1 = stable
  calibration_table - predicted vs actual default rate in 10 equal-sized groups
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score, roc_curve


def gini(y, p) -> float:
    return 2 * roc_auc_score(y, p) - 1


def ks(y, p) -> float:
    fpr, tpr, _ = roc_curve(y, p)
    return float(np.max(tpr - fpr))


def brier(y, p) -> float:
    y, p = np.asarray(y, float), np.asarray(p, float)
    return float(np.mean((p - y) ** 2))


def calibration_table(y, p, groups: int = 10) -> pd.DataFrame:
    """Clients sorted by predicted PD into equal-sized groups: predicted vs actual rate."""
    df = pd.DataFrame({"y": np.asarray(y), "p": np.asarray(p)})
    df["group"] = pd.qcut(df.p.rank(method="first"), groups, labels=range(1, groups + 1))
    t = df.groupby("group", observed=True).agg(clients=("y", "size"), predicted=("p", "mean"), actual=("y", "mean"))
    return t


def psi(expected, actual, groups: int = 10) -> float:
    """Population stability index of a score between two populations."""
    expected, actual = np.asarray(expected, float), np.asarray(actual, float)
    edges = np.unique(np.quantile(expected, np.linspace(0, 1, groups + 1)))
    edges[0], edges[-1] = -np.inf, np.inf
    e = np.histogram(expected, edges)[0] / len(expected)
    a = np.histogram(actual, edges)[0] / len(actual)
    e, a = np.clip(e, 1e-6, None), np.clip(a, 1e-6, None)
    return float(np.sum((a - e) * np.log(a / e)))
