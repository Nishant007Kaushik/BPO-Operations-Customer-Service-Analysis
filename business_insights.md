# Business Insights: BPO Operations & Customer Service Performance

Analysis of 60,000 interactions from a synthetic BPO operations dataset (8 teams, Jan–Dec 2025). Analysis only, no predictive modelling.

## Executive Summary

The operation meets SLA on 84.89% of interactions, but performance is not evenly spread. Service levels fall sharply in two daily peak windows, one team (T05) trails on every quality KPI, and two issue types (Technical Support and Complaint) drive most escalations. High-priority interactions are the most exposed: only 55.85% meet SLA because they wait as long as low-priority ones but have tighter targets.

## Baseline KPIs

| KPI | Value |
|---|---|
| Interactions | 60,000 |
| Average handle time (AHT) | 11.18 min |
| FCR (recorded) | 74.00% |
| FCR (strict) | 72.82% |
| SLA met | 84.89% |
| Escalation rate | 9.74% |
| Transfer rate | 8.30% |
| Repeat interaction rate | 13.28% |
| CSAT | 3.98 |

## Findings

### 1. SLA drops in peak hours across every team
- SLA falls from about 90% to about 80% in hours 9–11 and 14–16.
- These windows hold 52% of interaction volume and about 69% of SLA breaches.
- The pattern appears in all teams, so it is a capacity and scheduling issue, not a single-team issue.
- **Recommendation:** shift staffing and breaks toward the two peak windows, and review whether shift start times match demand.

### 2. Team T05 trails on all quality KPIs
- Strict FCR 67.65% (overall 72.82%), SLA 81.13% (84.89%), CSAT 3.90 (3.98), escalation 10.80% (9.74%).
- The gap holds across all hours and issue types, which points to a team-level cause such as training, coaching or process.
- **Recommendation:** run a call-quality review and coaching plan for T05, then track strict FCR and escalation monthly against the other teams.

### 3. Technical Support and Complaint drive escalations
- Together they are 31% of interactions but 69% of escalations (escalation rates: Complaint 26.98%, Technical Support 19.28%).
- They also have the longest AHT, the lowest CSAT and the most repeat interactions.
- **Recommendation:** build escalation playbooks and knowledge-base articles for these two issue types, and route them to more experienced agents.

### 4. High-priority interactions miss SLA most often
- SLA by priority: Low 98.40%, Medium 86.10%, High 55.85%.
- Average waits are about the same across priorities (about 3.3 min), but high-priority targets are tighter. The queue does not appear to treat priority differently.
- **Recommendation:** introduce priority-based queueing or routing so high-priority interactions are answered first.

### 5. August SLA dip
- Monthly SLA falls to about 80.1% in August, against roughly 85–86% in most other months.
- The dip appears across almost all teams and segments, which suggests an operation-wide cause (for example leave, attrition or a volume spike).
- **Recommendation:** check August staffing and volume, and plan leave and cover for the same period next year.

### 6. Agent workload varies widely with no visible link to quality
- Interactions per agent range from 140 to 1,244 (about 9x).
- CSAT is flat across that range, so heavier workload does not show up as lower satisfaction in this data.
- **Recommendation:** rebalance workload for fairness and capacity reasons. Do not assume quality will improve from it.

### 7. Resolution and follow-up strongly affect CSAT
- CSAT is 4.22 for Resolved interactions and 2.36 for Unresolved.
- CSAT is 3.03 when a follow-up was required, against 4.22 when it was not.
- **Recommendation:** focus on first-contact resolution and reduce follow-up requirements, since both move CSAT more than handle time does.

## Data Notes

- Raw data had 60,180 rows. After cleaning, 60,000 rows and 35 columns remain, with 7 `DQ_` flag columns marking corrected or recovered values.
- 40 interactions (0.07%) have no date. They are excluded from monthly trends but included in all totals and KPIs.
- **Strict FCR** counts an interaction only if First_Call_Resolution is Yes **and** Resolution_Status is Resolved. Recorded FCR uses First_Call_Resolution alone.
- **AHT** is interaction duration plus hold time plus after-call work.
- KPI values match across MySQL, Excel and Power BI.

## Limitations

- The dataset is synthetic, so findings show the analysis method and not real operational results.
- The analysis is descriptive. Relationships such as priority vs SLA or workload vs CSAT are associations, not proven causes.
- Recommendations are suggestions for investigation, not tested interventions.