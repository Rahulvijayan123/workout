#!/usr/bin/env python3
import json, sys
from collections import defaultdict

MAIN = {"squat","bench","deadlift","ohp"}

def key(r): return (r["user_id"], r["date"], r["session_type"])

def load_jsonl(path):
    out = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                out.append(json.loads(line))
    return out

def find_by_lift(lst, lift):
    for x in lst:
        if x.get("lift") == lift:
            return x
    return None

def in_range(x, lo, hi): return (x >= lo) and (x <= hi)

def main():
    if len(sys.argv) != 3:
        print("Usage: score_predictions.py dataset.jsonl predictions.jsonl")
        sys.exit(2)

    ds = load_jsonl(sys.argv[1])
    pr = load_jsonl(sys.argv[2])
    pred = {key(r): r for r in pr}

    total = agree = 0
    abs_err = []
    decision_ok = decision_total = 0
    per_user = defaultdict(lambda: {"total":0,"agree":0,"abs_err":[], "decision_ok":0,"decision_total":0})

    for r in ds:
        exp_list = r.get("expected", {}).get("session_prescription_for_today")
        if not exp_list:
            continue
        k = key(r)
        if k not in pred:
            continue
        pred_list = pred[k].get("engine_output", {}).get("session_prescription_for_today", [])
        for e in exp_list:
            lift = e.get("lift")
            if lift not in MAIN:
                continue
            p = find_by_lift(pred_list, lift)
            if not p:
                continue

            total += 1
            per_user[r["user_id"]]["total"] += 1

            e_w = float(e.get("prescribed_weight_lb") or 0)
            p_w = float(p.get("prescribed_weight_lb") or 0)
            lo, hi = e.get("acceptable_range_lb") or [e_w, e_w]
            lo = float(lo); hi = float(hi)

            err = abs(e_w - p_w)
            abs_err.append(err)
            per_user[r["user_id"]]["abs_err"].append(err)

            if in_range(p_w, lo, hi):
                agree += 1
                per_user[r["user_id"]]["agree"] += 1

            e_d = e.get("decision")
            p_d = p.get("decision")
            if e_d is not None and p_d is not None:
                decision_total += 1
                per_user[r["user_id"]]["decision_total"] += 1
                if e_d == p_d:
                    decision_ok += 1
                    per_user[r["user_id"]]["decision_ok"] += 1

    mae = sum(abs_err)/len(abs_err) if abs_err else float("nan")
    print(f"Main lift load agreement: {agree}/{total} = {agree/total if total else 0:.2f}")
    print(f"Main lift MAE (point label): {mae:.2f} lb")
    print(f"Decision accuracy: {decision_ok}/{decision_total} = {decision_ok/decision_total if decision_total else 0:.2f}")
    print("Per-user:")
    for u, s in sorted(per_user.items()):
        user_mae = (sum(s['abs_err'])/len(s['abs_err'])) if s['abs_err'] else float('nan')
        agree_rate = s["agree"]/s["total"] if s["total"] else 0
        dec_rate = s["decision_ok"]/s["decision_total"] if s["decision_total"] else 0
        print(f"  {u}: agree {agree_rate:.2f}, MAE {user_mae:.2f} lb, decisionAcc {dec_rate:.2f}, n={s['total']}")

if __name__ == "__main__":
    main()
