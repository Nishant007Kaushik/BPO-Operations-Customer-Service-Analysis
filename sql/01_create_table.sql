CREATE DATABASE IF NOT EXISTS bpo_operations;
USE bpo_operations;

DROP TABLE IF EXISTS bpo_interactions;

CREATE TABLE bpo_interactions (
    Interaction_ID            VARCHAR(12)   NOT NULL,
    Interaction_Date          DATE          NULL,
    Interaction_Time          TIME          NULL,
    Customer_ID               VARCHAR(12)   NOT NULL,
    Client_ID                 VARCHAR(10)   NOT NULL,
    Team_ID                   VARCHAR(10)   NOT NULL,
    Agent_ID                  VARCHAR(10)   NULL,
    Channel                   VARCHAR(20)   NOT NULL,
    Call_Type                 VARCHAR(20)   NOT NULL,
    Issue_Category            VARCHAR(40)   NOT NULL,
    Issue_Subcategory         VARCHAR(60)   NOT NULL,
    Priority                  VARCHAR(10)   NOT NULL,
    Interaction_Duration_Min  DECIMAL(8,2)  NULL,
    Wait_Time_Min             DECIMAL(8,2)  NULL,
    Hold_Time_Min             DECIMAL(8,2)  NULL,
    After_Call_Work_Min       DECIMAL(8,2)  NULL,
    Resolution_Status         VARCHAR(30)   NOT NULL,
    First_Call_Resolution     VARCHAR(5)    NOT NULL,
    Escalation_Status         VARCHAR(20)   NOT NULL,
    Transfer_Status           VARCHAR(20)   NOT NULL,
    SLA_Target_Min            INT           NOT NULL,
    SLA_Met                   VARCHAR(5)    NOT NULL,
    Customer_Satisfaction     DECIMAL(3,1)  NULL,
    Follow_Up_Required        VARCHAR(5)    NOT NULL,
    Repeat_Interaction        VARCHAR(5)    NOT NULL,
    Disposition               VARCHAR(40)   NOT NULL,
    Region                    VARCHAR(20)   NOT NULL,
    Shift                     VARCHAR(20)   NOT NULL,
    DQ_Team_Recovered         TINYINT       NOT NULL,
    DQ_Agent_Missing          TINYINT       NOT NULL,
    DQ_Duration_Corrected     TINYINT       NOT NULL,
    DQ_Wait_Outlier           TINYINT       NOT NULL,
    DQ_SLA_Target_Corrected   TINYINT       NOT NULL,
    DQ_SLA_Mismatch           TINYINT       NOT NULL,
    DQ_FCR_Inconsistent       TINYINT       NOT NULL,
    PRIMARY KEY (Interaction_ID),
    INDEX idx_date    (Interaction_Date),
    INDEX idx_agent   (Agent_ID),
    INDEX idx_team    (Team_ID),
    INDEX idx_issue   (Issue_Category)
);

DESCRIBE bpo_interactions;