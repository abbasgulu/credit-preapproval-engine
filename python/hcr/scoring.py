"""Scoring with the saved models — written once, used everywhere.

In plain words: turns a client's facts into a risk number, using the model
files in models/. Every script that scores clients (the holdout exam, the
calibration, the scores written to Oracle) calls these functions, so the
formula exists in exactly one place.

A model first gives a *raw score* on the log-odds scale (minus infinity to
plus infinity, higher = riskier). A probability of default is
1 / (1 + exp(-raw score)). Stage 3g adjusts this with two calibration
numbers (a, b) kept in Oracle: PD = 1 / (1 + exp(-(a + b * raw score))).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd

from hcr.woe import Binning

MODELS = Path(__file__).resolve().parents[2] / "models"


def load_scorecard() -> dict:
    return json.loads((MODELS / "scorecard.json").read_text(encoding="utf-8"))


def load_lightgbm() -> tuple[lgb.Booster, dict]:
    meta = json.loads((MODELS / "lightgbm.json").read_text(encoding="utf-8"))
    return lgb.Booster(model_file=str(MODELS / "lightgbm.txt")), meta


def fingerprint(files=("scorecard.json", "lightgbm.txt")) -> dict:
    """SHA-256 of model files: proves exactly which models produced a result."""
    return {f: hashlib.sha256((MODELS / f).read_bytes()).hexdigest() for f in files}


def scorecard_raw(card: dict, data: pd.DataFrame) -> np.ndarray:
    """Log-odds of the scorecard: intercept + sum(weight x WoE)."""
    logit = np.full(len(data), card["intercept"], dtype=float)
    for f in card["features"]:
        b = Binning(feature=f["feature"], kind=f["kind"], edges=f["edges"],
                    categories=f["categories"], woe=f["woe"], iv=f["iv"])
        logit += f["coefficient"] * b.transform(data[f["feature"]]).to_numpy()
    return logit


def lightgbm_input(booster: lgb.Booster, meta: dict, data: pd.DataFrame) -> pd.DataFrame:
    """The model's features, prepared exactly as in training."""
    x = data[meta["features"]].copy()
    # text columns get exactly the category lists the model was trained with
    for col, cats in zip(meta["categorical"], booster.pandas_categorical or []):
        x[col] = pd.Categorical(x[col], categories=cats)
    return x


def lightgbm_raw(booster: lgb.Booster, meta: dict, data: pd.DataFrame) -> np.ndarray:
    """Log-odds of LightGBM (raw_score=True)."""
    return booster.predict(lightgbm_input(booster, meta, data), raw_score=True)


def lightgbm_contributions(booster: lgb.Booster, meta: dict, data: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    """SHAP values: how much each feature pushed each client's raw score up or down,
    compared with an average client. Returns (one column per feature, the average-client
    baseline). Baseline + sum of a client's columns = the client's raw score, exactly."""
    out = booster.predict(lightgbm_input(booster, meta, data), pred_contrib=True)
    return out[:, :-1], out[:, -1]


def to_pd(raw: np.ndarray, a: float = 0.0, b: float = 1.0) -> np.ndarray:
    """Probability of default from a raw score; a = 0, b = 1 means 'uncalibrated'.
    The same formula lives in Oracle as f_calibrate_pd (checked to match)."""
    return 1 / (1 + np.exp(-(a + b * np.asarray(raw, dtype=float))))
