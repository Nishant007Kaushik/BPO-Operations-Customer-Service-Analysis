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