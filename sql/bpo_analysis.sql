USE bpo_operations;

-- =====================================================================
-- SECTION 1: BASIC ANALYSIS
-- =====================================================================

-- Q1-Q5: Overall size of the operation
SELECT COUNT(*)                        AS total_interactions,
       COUNT(DISTINCT Customer_ID)     AS unique_customers,
       COUNT(DISTINCT Agent_ID)        AS total_agents,      -- NULL agents are ignored
       COUNT(DISTINCT Team_ID)         AS total_teams,
       COUNT(DISTINCT Client_ID)       AS total_clients
FROM bpo_interactions;

-- Q6: Interactions by channel (with share of total)
SELECT Channel,
       COUNT(*) AS interactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM bpo_interactions
GROUP BY Channel
ORDER BY interactions DESC;

-- Q7: Interactions by issue category
SELECT Issue_Category,
       COUNT(*) AS interactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM bpo_interactions
GROUP BY Issue_Category
ORDER BY interactions DESC;

-- Q8: Interactions by priority
SELECT Priority,
       COUNT(*) AS interactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM bpo_interactions
GROUP BY Priority
ORDER BY FIELD(Priority, 'High', 'Medium', 'Low');

-- =====================================================================
-- SECTION 2: TIME ANALYSIS
-- Rows with an invalid (NULL) date or time are excluded from these queries only.
-- =====================================================================

-- Q9: Daily interaction volume
SELECT Interaction_Date, COUNT(*) AS interactions
FROM bpo_interactions
WHERE Interaction_Date IS NOT NULL
GROUP BY Interaction_Date
ORDER BY Interaction_Date;

-- Q10 (improved): flag partial weeks
SELECT DATE_SUB(Interaction_Date, INTERVAL WEEKDAY(Interaction_Date) DAY) AS week_start,
       COUNT(*)                          AS interactions,
       COUNT(DISTINCT Interaction_Date)  AS days_with_data
FROM bpo_interactions
WHERE Interaction_Date IS NOT NULL
GROUP BY week_start
ORDER BY week_start;

-- Q11 (improved): monthly volume normalised per day
WITH monthly AS (
    SELECT DATE_FORMAT(Interaction_Date, '%Y-%m') AS month,
           COUNT(*)                          AS interactions,
           COUNT(DISTINCT Interaction_Date)  AS days_with_data
    FROM bpo_interactions
    WHERE Interaction_Date IS NOT NULL
    GROUP BY DATE_FORMAT(Interaction_Date, '%Y-%m')
)
SELECT month, interactions, days_with_data,
       ROUND(interactions / days_with_data, 1) AS avg_per_day,
       ROUND(100.0 * (interactions / days_with_data
             - LAG(interactions / days_with_data) OVER (ORDER BY month))
             / LAG(interactions / days_with_data) OVER (ORDER BY month), 1) AS per_day_change_pct
FROM monthly
ORDER BY month;

-- Q12: Interaction volume by hour of day
SELECT HOUR(Interaction_Time) AS hour_of_day,
       COUNT(*) AS interactions
FROM bpo_interactions
WHERE Interaction_Time IS NOT NULL
GROUP BY HOUR(Interaction_Time)
ORDER BY hour_of_day;

-- Q13: Peak interaction hours (top 5, using RANK)
WITH hourly AS (
    SELECT HOUR(Interaction_Time) AS hour_of_day,
           COUNT(*) AS interactions
    FROM bpo_interactions
    WHERE Interaction_Time IS NOT NULL
    GROUP BY HOUR(Interaction_Time)
),
ranked AS (
    SELECT hour_of_day, interactions,
           RANK() OVER (ORDER BY interactions DESC) AS rnk
    FROM hourly
)
SELECT hour_of_day, interactions, rnk
FROM ranked
WHERE rnk <= 5
ORDER BY rnk;

-- Q14: Peak days of the week
-- Total volume depends on how many of each weekday exist in the year,
-- so the average per calendar day is the fairer comparison.
SELECT DAYNAME(Interaction_Date)                   AS day_name,
       COUNT(*)                                    AS total_interactions,
       COUNT(DISTINCT Interaction_Date)            AS days_in_data,
       ROUND(COUNT(*) / COUNT(DISTINCT Interaction_Date), 1) AS avg_interactions_per_day
FROM bpo_interactions
WHERE Interaction_Date IS NOT NULL
GROUP BY WEEKDAY(Interaction_Date), DAYNAME(Interaction_Date)
ORDER BY WEEKDAY(Interaction_Date);
-- =====================================================================
-- SECTION 3: AGENT ANALYSIS
-- Rows with NULL Agent_ID (300) are excluded from agent analysis only.
-- AHT = duration + hold + after-call work; rows with a NULL hold time
-- (42 voice calls) are skipped automatically by AVG().
-- Strict FCR = FCR 'Yes' AND status 'Resolved' (recorded FCR also shown).
-- =====================================================================

-- Q15-Q21: Agent scorecard
CREATE OR REPLACE VIEW vw_agent_scorecard AS
SELECT
    Agent_ID,
    MAX(Team_ID)  AS Team_ID,                         -- each agent belongs to one team
    COUNT(*)      AS interactions,
    ROUND(AVG(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min), 2) AS aht_min,
    ROUND(100.0 * SUM(CASE WHEN Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS resolution_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_recorded_pct,
    ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_strict_pct,
    ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_recorded_pct,
    ROUND(AVG(Customer_Satisfaction), 2) AS csat_avg,
    COUNT(Customer_Satisfaction)         AS csat_responses,
    ROUND(100.0 * SUM(CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END) / COUNT(*), 2) AS escalation_rate_pct
FROM bpo_interactions
WHERE Agent_ID IS NOT NULL
GROUP BY Agent_ID;

SELECT * FROM vw_agent_scorecard ORDER BY interactions DESC;
-- How wide is the spread across agents?
SELECT MIN(interactions) AS min_vol,      MAX(interactions) AS max_vol,      ROUND(AVG(interactions)) AS avg_vol,
       MIN(aht_min) AS min_aht,           MAX(aht_min) AS max_aht,
       MIN(resolution_rate_pct) AS min_res, MAX(resolution_rate_pct) AS max_res,
       MIN(fcr_recorded_pct) AS min_fcr,  MAX(fcr_recorded_pct) AS max_fcr,
       MIN(sla_recorded_pct) AS min_sla,  MAX(sla_recorded_pct) AS max_sla,
       MIN(csat_avg) AS min_csat,         MAX(csat_avg) AS max_csat,
       MIN(escalation_rate_pct) AS min_esc, MAX(escalation_rate_pct) AS max_esc
FROM vw_agent_scorecard;
-- Q22-Q23: Segment agents using percentile ranks
-- High performer  = top quartile on BOTH strict FCR and CSAT
-- Needs attention = bottom quartile on BOTH strict FCR and CSAT
-- AHT is shown but not used to judge quality: a low AHT can mean rushing.
CREATE OR REPLACE VIEW vw_agent_segments AS
WITH ranked AS (
    SELECT *,
           PERCENT_RANK() OVER (ORDER BY fcr_strict_pct) AS fcr_pr,
           PERCENT_RANK() OVER (ORDER BY csat_avg)       AS csat_pr,
           NTILE(4)       OVER (ORDER BY interactions)   AS volume_quartile   -- 4 = busiest
    FROM vw_agent_scorecard
)
SELECT Agent_ID, Team_ID, interactions, volume_quartile,
       aht_min, fcr_strict_pct, csat_avg, sla_recorded_pct, escalation_rate_pct,
       CASE WHEN fcr_pr >= 0.75 AND csat_pr >= 0.75 THEN 'High performer'
            WHEN fcr_pr <= 0.25 AND csat_pr <= 0.25 THEN 'Needs attention'
            ELSE 'Middle' END AS segment
FROM ranked;

SELECT segment, COUNT(*) AS agents FROM vw_agent_segments GROUP BY segment;

-- Q22: high performers
SELECT * FROM vw_agent_segments WHERE segment = 'High performer' ORDER BY csat_avg DESC;

-- Q23: agents needing attention
SELECT * FROM vw_agent_segments WHERE segment = 'Needs attention' ORDER BY csat_avg;

-- Business question B: high volume but poor quality
SELECT * FROM vw_agent_segments
WHERE segment = 'Needs attention' AND volume_quartile = 4
ORDER BY interactions DESC;
-- =====================================================================
-- SECTION 4: TEAM ANALYSIS
-- Metrics are calculated from interaction rows, not by averaging agent averages.
-- =====================================================================

-- Q24-Q29: Team scorecard
CREATE OR REPLACE VIEW vw_team_scorecard AS
SELECT
    Team_ID,
    COUNT(*)                                             AS interactions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_volume,
    COUNT(DISTINCT Agent_ID)                             AS agents,
    ROUND(COUNT(Agent_ID) / COUNT(DISTINCT Agent_ID))    AS interactions_per_agent,
    ROUND(AVG(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min), 2) AS aht_min,
    ROUND(100.0 * SUM(CASE WHEN Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS resolution_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_recorded_pct,
    ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_strict_pct,
    ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_recorded_pct,
    ROUND(AVG(Customer_Satisfaction), 2)                 AS csat_avg,
    ROUND(100.0 * SUM(CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END) / COUNT(*), 2) AS escalation_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Transfer_Status = 'Transferred' THEN 1 ELSE 0 END) / COUNT(*), 2) AS transfer_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Repeat_Interaction = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM bpo_interactions
GROUP BY Team_ID;

SELECT * FROM vw_team_scorecard ORDER BY Team_ID;

-- Where do the high performers and needs-attention agents sit?
SELECT Team_ID,
       SUM(CASE WHEN segment = 'High performer'  THEN 1 ELSE 0 END) AS high_performers,
       SUM(CASE WHEN segment = 'Middle'          THEN 1 ELSE 0 END) AS middle,
       SUM(CASE WHEN segment = 'Needs attention' THEN 1 ELSE 0 END) AS needs_attention
FROM vw_agent_segments
GROUP BY Team_ID
ORDER BY needs_attention DESC;

-- Does higher volume go with lower quality? (answers business question B properly)
SELECT volume_quartile,
       COUNT(*)                          AS agents,
       ROUND(AVG(interactions))          AS avg_interactions,
       ROUND(AVG(fcr_strict_pct), 2)     AS avg_fcr_strict,
       ROUND(AVG(csat_avg), 2)           AS avg_csat,
       ROUND(AVG(aht_min), 2)            AS avg_aht,
       ROUND(AVG(escalation_rate_pct), 2) AS avg_escalation
FROM vw_agent_segments
GROUP BY volume_quartile
ORDER BY volume_quartile;
SELECT Team_ID, interactions, aht_min, fcr_strict_pct,
       sla_recorded_pct, csat_avg, escalation_rate_pct
FROM vw_team_scorecard
ORDER BY fcr_strict_pct;
-- Is T05's strict FCR gap broad or concentrated in certain issues?
WITH cat AS (
    SELECT Issue_Category,
           SUM(CASE WHEN Team_ID = 'T05' THEN 1 ELSE 0 END) AS t05_interactions,
           ROUND(100.0 * SUM(CASE WHEN Team_ID = 'T05' AND First_Call_Resolution = 'Yes'
                                   AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END)
                 / NULLIF(SUM(CASE WHEN Team_ID = 'T05' THEN 1 ELSE 0 END), 0), 2) AS t05_fcr_strict,
           ROUND(100.0 * SUM(CASE WHEN Team_ID <> 'T05' AND First_Call_Resolution = 'Yes'
                                   AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END)
                 / NULLIF(SUM(CASE WHEN Team_ID <> 'T05' THEN 1 ELSE 0 END), 0), 2) AS other_teams_fcr_strict
    FROM bpo_interactions
    GROUP BY Issue_Category
)
SELECT Issue_Category, t05_interactions, t05_fcr_strict, other_teams_fcr_strict,
       ROUND(t05_fcr_strict - other_teams_fcr_strict, 2) AS gap_pts
FROM cat
ORDER BY gap_pts;
-- =====================================================================
-- SECTION 5: CUSTOMER SERVICE / ISSUE ANALYSIS (Q30-Q35)
-- Note: the dataset has no "time to resolve" column, so AHT is used as the
-- measure of effort per issue. Say this in your README.
-- =====================================================================

CREATE OR REPLACE VIEW vw_issue_scorecard AS
SELECT
    Issue_Category,
    COUNT(*)                                            AS interactions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_volume,
    ROUND(AVG(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min), 2) AS aht_min,
    ROUND(100.0 * SUM(CASE WHEN Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS resolution_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_strict_pct,
    ROUND(100.0 * SUM(CASE WHEN Escalation_Status = 'Escalated'   THEN 1 ELSE 0 END) / COUNT(*), 2) AS escalation_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Repeat_Interaction = 'Yes'        THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Transfer_Status = 'Transferred'   THEN 1 ELSE 0 END) / COUNT(*), 2) AS transfer_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes'                   THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_recorded_pct,
    ROUND(AVG(Customer_Satisfaction), 2)                AS csat_avg
FROM bpo_interactions
GROUP BY Issue_Category;

-- Q30-Q35 in one table, with a rank for each problem metric (1 = worst)
SELECT Issue_Category, interactions, pct_of_volume, aht_min,
       resolution_rate_pct, escalation_rate_pct, repeat_rate_pct, csat_avg,
       RANK() OVER (ORDER BY escalation_rate_pct DESC) AS escalation_rank,
       RANK() OVER (ORDER BY resolution_rate_pct)      AS lowest_resolution_rank,
       RANK() OVER (ORDER BY repeat_rate_pct DESC)     AS repeat_rank,
       RANK() OVER (ORDER BY csat_avg)                 AS lowest_csat_rank,
       RANK() OVER (ORDER BY aht_min DESC)             AS longest_aht_rank
FROM vw_issue_scorecard
ORDER BY interactions DESC;

-- Q30 (detail): the 10 most common issue subcategories, with how concentrated demand is
WITH sub AS (
    SELECT Issue_Category, Issue_Subcategory,
           COUNT(*) AS interactions,
           ROUND(100.0 * SUM(CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END) / COUNT(*), 2) AS escalation_rate_pct,
           ROUND(100.0 * SUM(CASE WHEN First_Call_Resolution = 'Yes' AND Resolution_Status = 'Resolved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fcr_strict_pct,
           ROUND(100.0 * SUM(CASE WHEN Repeat_Interaction = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct,
           ROUND(AVG(Customer_Satisfaction), 2) AS csat_avg
    FROM bpo_interactions
    GROUP BY Issue_Category, Issue_Subcategory
)
SELECT Issue_Category, Issue_Subcategory, interactions,
       ROUND(100.0 * interactions / SUM(interactions) OVER (), 2) AS pct_of_volume,
       ROUND(100.0 * SUM(interactions) OVER (ORDER BY interactions DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / SUM(interactions) OVER (), 2) AS cumulative_pct,
       escalation_rate_pct, fcr_strict_pct, repeat_rate_pct, csat_avg
FROM sub
ORDER BY interactions DESC
LIMIT 10;
-- Workload by issue: share of interactions vs share of handling time
-- Rows with a NULL hold time (42 voice calls) are skipped in the hour totals.
SELECT Issue_Category,
       COUNT(*) AS interactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_interactions,
       ROUND(SUM(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min) / 60) AS handling_hours,
       ROUND(100.0 * SUM(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min)
             / SUM(SUM(Interaction_Duration_Min + Hold_Time_Min + After_Call_Work_Min)) OVER (), 2) AS pct_of_handling_time
FROM bpo_interactions
GROUP BY Issue_Category
ORDER BY handling_hours DESC;
-- =====================================================================
-- SECTION 6: SLA ANALYSIS (Q36-Q40)
-- Recorded SLA = SLA_Met column | Recalculated = Wait_Time_Min <= SLA_Target_Min
-- Average wait excludes the 60 flagged outliers (DQ_Wait_Outlier = 1).
-- =====================================================================

-- Q36: SLA met vs breached, two ways
SELECT 'Recorded (SLA_Met column)' AS method,
       SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) AS met,
       SUM(CASE WHEN SLA_Met = 'No'  THEN 1 ELSE 0 END) AS breached,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS compliance_pct
FROM bpo_interactions
UNION ALL
SELECT 'Recalculated (wait <= target)',
       SUM(CASE WHEN Wait_Time_Min <= SLA_Target_Min THEN 1 ELSE 0 END),
       SUM(CASE WHEN Wait_Time_Min >  SLA_Target_Min THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN Wait_Time_Min <= SLA_Target_Min THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM bpo_interactions;

-- Q37: SLA by team
SELECT Team_ID, COUNT(*) AS interactions,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct,
       ROUND(AVG(CASE WHEN DQ_Wait_Outlier = 0 THEN Wait_Time_Min END), 2) AS avg_wait_min
FROM bpo_interactions
GROUP BY Team_ID
ORDER BY sla_pct;

-- Q38: SLA by hour (compare with volume to see whether weak hours are the busy ones)
SELECT HOUR(Interaction_Time) AS hour_of_day, COUNT(*) AS interactions,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct,
       ROUND(AVG(CASE WHEN DQ_Wait_Outlier = 0 THEN Wait_Time_Min END), 2) AS avg_wait_min
FROM bpo_interactions
WHERE Interaction_Time IS NOT NULL
GROUP BY HOUR(Interaction_Time)
ORDER BY hour_of_day;

-- Q39a: SLA by priority
SELECT Priority, COUNT(*) AS interactions,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct,
       ROUND(AVG(CASE WHEN DQ_Wait_Outlier = 0 THEN Wait_Time_Min END), 2) AS avg_wait_min
FROM bpo_interactions
GROUP BY Priority
ORDER BY FIELD(Priority, 'High', 'Medium', 'Low');

-- Q39b: SLA by channel (targets differ by channel, so compare compliance, not wait)
SELECT Channel, COUNT(*) AS interactions,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct,
       ROUND(AVG(CASE WHEN DQ_Wait_Outlier = 0 THEN Wait_Time_Min END), 2) AS avg_wait_min
FROM bpo_interactions
GROUP BY Channel
ORDER BY sla_pct;

-- Q40: Which months were weakest?
WITH monthly AS (
    SELECT DATE_FORMAT(Interaction_Date, '%Y-%m') AS month,
           COUNT(*) AS interactions,
           ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct,
           ROUND(AVG(CASE WHEN DQ_Wait_Outlier = 0 THEN Wait_Time_Min END), 2) AS avg_wait_min
    FROM bpo_interactions
    WHERE Interaction_Date IS NOT NULL
    GROUP BY DATE_FORMAT(Interaction_Date, '%Y-%m')
)
SELECT month, interactions, sla_pct, avg_wait_min,
       ROUND(sla_pct - AVG(sla_pct) OVER (), 2) AS vs_avg_of_months,
       RANK() OVER (ORDER BY sla_pct)           AS worst_rank
FROM monthly
ORDER BY month;

-- Business question D: which issue categories contribute most to SLA breaches?
SELECT Issue_Category, COUNT(*) AS interactions,
       SUM(CASE WHEN SLA_Met = 'No' THEN 1 ELSE 0 END) AS breaches,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_interactions,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'No' THEN 1 ELSE 0 END)
             / SUM(SUM(CASE WHEN SLA_Met = 'No' THEN 1 ELSE 0 END)) OVER (), 2) AS pct_of_breaches,
       ROUND(100.0 * SUM(CASE WHEN SLA_Met = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS sla_pct
FROM bpo_interactions
GROUP BY Issue_Category
ORDER BY pct_of_breaches DESC;
-- =====================================================================
-- SECTION 7: ESCALATION ANALYSIS (Q41-Q45)
-- Escalation rate = Escalation_Status = 'Escalated' / all interactions
-- =====================================================================

-- Q41: overall escalation rate
SELECT COUNT(*) AS interactions,
       SUM(CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END) AS escalated,
       ROUND(100.0 * SUM(CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END) / COUNT(*), 2) AS escalation_rate_pct
FROM bpo_interactions;

-- Q42-Q44: by issue, team, priority (and channel), with each segment's share of all escalations
WITH e AS (
    SELECT Issue_Category, Team_ID, Priority, Channel,
           CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END AS esc
    FROM bpo_interactions
),
dims AS (
    SELECT 'Issue' AS dimension, Issue_Category AS segment, COUNT(*) AS interactions, SUM(esc) AS escalated FROM e GROUP BY Issue_Category
    UNION ALL SELECT 'Team',     Team_ID,  COUNT(*), SUM(esc) FROM e GROUP BY Team_ID
    UNION ALL SELECT 'Priority', Priority, COUNT(*), SUM(esc) FROM e GROUP BY Priority
    UNION ALL SELECT 'Channel',  Channel,  COUNT(*), SUM(esc) FROM e GROUP BY Channel
)
SELECT dimension, segment, interactions, escalated,
       ROUND(100.0 * escalated / interactions, 2) AS escalation_rate_pct,
       ROUND(100.0 * interactions / SUM(interactions) OVER (PARTITION BY dimension), 2) AS pct_of_interactions,
       ROUND(100.0 * escalated   / SUM(escalated)    OVER (PARTITION BY dimension), 2) AS pct_of_escalations
FROM dims
ORDER BY dimension, escalation_rate_pct DESC;

-- Q45a: is it the issue, the priority, or both? (escalation % by issue and priority)
SELECT Issue_Category,
       ROUND(100.0 * AVG(CASE WHEN Priority = 'High'   THEN (Escalation_Status = 'Escalated') END), 1) AS high_pct,
       ROUND(100.0 * AVG(CASE WHEN Priority = 'Medium' THEN (Escalation_Status = 'Escalated') END), 1) AS medium_pct,
       ROUND(100.0 * AVG(CASE WHEN Priority = 'Low'    THEN (Escalation_Status = 'Escalated') END), 1) AS low_pct
FROM bpo_interactions
GROUP BY Issue_Category
ORDER BY high_pct DESC;

-- Q45b: which interaction characteristics go with escalation?
-- Association only: a long interaction may be a result of escalation, not a cause.
WITH f AS (
    SELECT CASE WHEN Escalation_Status = 'Escalated' THEN 1 ELSE 0 END AS esc,
           Interaction_Duration_Min AS dur, Hold_Time_Min AS hold, Wait_Time_Min AS wait,
           Repeat_Interaction, Transfer_Status
    FROM bpo_interactions
)
SELECT 'Duration' AS factor,
       CASE WHEN dur < 5 THEN '1: under 5 min' WHEN dur < 8 THEN '2: 5 to 8' WHEN dur < 12 THEN '3: 8 to 12' ELSE '4: 12+' END AS band,
       COUNT(*) AS n, ROUND(100.0 * AVG(esc), 2) AS escalation_rate_pct
FROM f GROUP BY 2
UNION ALL
SELECT 'Hold time',
       CASE WHEN hold = 0 THEN '1: none' WHEN hold <= 3 THEN '2: up to 3 min' ELSE '3: over 3 min' END,
       COUNT(*), ROUND(100.0 * AVG(esc), 2)
FROM f WHERE hold IS NOT NULL GROUP BY 2
UNION ALL
SELECT 'Wait time',
       CASE WHEN wait <= 2 THEN '1: up to 2 min' WHEN wait <= 4 THEN '2: 2 to 4' WHEN wait <= 8 THEN '3: 4 to 8' ELSE '4: over 8' END,
       COUNT(*), ROUND(100.0 * AVG(esc), 2)
FROM f GROUP BY 2
UNION ALL
SELECT 'Repeat contact', CASE WHEN Repeat_Interaction = 'Yes' THEN 'Repeat' ELSE 'First contact' END,
       COUNT(*), ROUND(100.0 * AVG(esc), 2)
FROM f GROUP BY 2
UNION ALL
SELECT 'Transfer', Transfer_Status, COUNT(*), ROUND(100.0 * AVG(esc), 2)
FROM f GROUP BY 2
ORDER BY factor, band;