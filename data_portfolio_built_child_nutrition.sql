-- =========================================================================
-- PROJECT: Monthly Nutrition & Child Growth Monitoring
-- PHASE 1: DATABASE & SCHEMA SETUP
-- =========================================================================

-- Create and use database (Uncomment if running for the very first time)
-- CREATE DATABASE malnutrition_child;
-- GO
USE malnutrition_child;
GO

-- Create Clinic Dimension
IF OBJECT_ID('Dim_Clinic', 'U') IS NULL
CREATE TABLE Dim_Clinic (
    ClinicID INT NOT NULL,
    ClinicName VARCHAR(100) NOT NULL,
    District VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Dim_Clinic PRIMARY KEY (ClinicID)
);
GO

-- Create Child Dimension
IF OBJECT_ID('Dim_Child', 'U') IS NULL
CREATE TABLE Dim_Child (
    ChildID INT NOT NULL,
    Gender VARCHAR(10) NOT NULL,
    DateOfBirth DATE NOT NULL,
    CONSTRAINT PK_Dim_Child PRIMARY KEY (ChildID),
    CONSTRAINT CHK_Gender CHECK (Gender IN ('Male', 'Female')) 
);
GO

-- Create Fact Table
IF OBJECT_ID('Fact_Screenings', 'U') IS NULL
CREATE TABLE Fact_Screenings (
    ScreeningID INT NOT NULL,
    ChildID INT NOT NULL,
    ClinicID INT NOT NULL,
    ScreeningDate DATE NOT NULL,
    AgeInMonths INT NOT NULL,
    Weight_kg DECIMAL(5,2) NULL,
    Height_cm DECIMAL(5,2) NULL,
    MUAC_cm DECIMAL(4,1) NULL,
    Malnutrition_Status VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Fact_Screenings PRIMARY KEY (ScreeningID),
    CONSTRAINT FK_Fact_Child FOREIGN KEY (ChildID) REFERENCES Dim_Child(ChildID),
    CONSTRAINT FK_Fact_Clinic FOREIGN KEY (ClinicID) REFERENCES Dim_Clinic(ClinicID),
    CONSTRAINT CHK_Age CHECK (AgeInMonths >= 0)
);
GO

-- =========================================================================
-- PHASE 2: ELT PIPELINE (EXTRACT, LOAD, TRANSFORM)
-- =========================================================================

-- STEP 1: Clear out existing data and temp tables for a clean run
DELETE FROM Fact_Screenings;
DELETE FROM Dim_Child;
DELETE FROM Dim_Clinic;

IF OBJECT_ID('tempdb..#Stage_Child') IS NOT NULL DROP TABLE #Stage_Child;
IF OBJECT_ID('tempdb..#Stage_Screenings') IS NOT NULL DROP TABLE #Stage_Screenings;
GO

-- STEP 2: Load Dim_Clinic directly (No dates to transform)
BULK INSERT Dim_Clinic
FROM 'C:\Users\manir\SQL\child_nutrition\dim_clinics.csv'
WITH (
    FIRSTROW = 2, 
    FIELDTERMINATOR = ',', 
    ROWTERMINATOR = '\n', 
    CODEPAGE = '65001'
);
GO

-- STEP 3: Stage and Load Dim_Child (Transforming dd/MM/yyyy)
CREATE TABLE #Stage_Child (
    ChildID INT,
    Gender VARCHAR(10),
    DateOfBirth VARCHAR(50) 
);

BULK INSERT #Stage_Child
FROM 'C:\Users\manir\SQL\child_nutrition\dim_children.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');

INSERT INTO Dim_Child (ChildID, Gender, DateOfBirth)
SELECT 
    ChildID, 
    Gender, 
    CONVERT(DATE, DateOfBirth, 103)
FROM #Stage_Child;
GO

-- STEP 4: Stage and Load Fact_Screenings (Robust date & line-break handling)
CREATE TABLE #Stage_Screenings (
    ScreeningID INT,
    ChildID INT,
    ClinicID INT,
    ScreeningDate VARCHAR(50), 
    AgeInMonths INT,
    Weight_kg DECIMAL(5,2),
    Height_cm DECIMAL(5,2),
    MUAC_cm DECIMAL(4,1),
    Malnutrition_Status VARCHAR(20)
);

BULK INSERT #Stage_Screenings
FROM 'C:\Users\manir\SQL\child_nutrition\fact_screenings.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');

INSERT INTO Fact_Screenings (ScreeningID, ChildID, ClinicID, ScreeningDate, AgeInMonths, Weight_kg, Height_cm, MUAC_cm, Malnutrition_Status)
SELECT
    ScreeningID,
    ChildID,
    ClinicID,
    COALESCE(
        TRY_CAST(ScreeningDate AS DATE), 
        TRY_CONVERT(DATE, ScreeningDate, 103)
    ),
    AgeInMonths,
    Weight_kg,
    Height_cm,
    MUAC_cm,
    REPLACE(Malnutrition_Status, CHAR(13), '') 
FROM #Stage_Screenings
WHERE ScreeningDate IS NOT NULL 
  AND ScreeningDate <> ''
  AND COALESCE(TRY_CAST(ScreeningDate AS DATE), TRY_CONVERT(DATE, ScreeningDate, 103)) IS NOT NULL;
GO

-- Analyze malnutrition rates by district and identify Severe Acute Malnutrition (SAM) trends 
-- 1. High-Level KPI: Overall Malnutrition Rates

CREATE VIEW vw_Overall_Malnutrition_Rates AS
SELECT 
    COUNT(ScreeningID) AS Total_Screenings,
    
    -- Count only SAM cases
    SUM(CASE WHEN Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) AS Total_SAM,
    
    -- Count only MAM cases
    SUM(CASE WHEN Malnutrition_Status = 'MAM' THEN 1 ELSE 0 END) AS Total_MAM,
    
    -- Calculate SAM Percentage
    CAST(SUM(CASE WHEN Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) * 100.0 / COUNT(ScreeningID) AS DECIMAL(5,2)) AS SAM_Percentage,
    
    -- Calculate MAM Percentage
    CAST(SUM(CASE WHEN Malnutrition_Status = 'MAM' THEN 1 ELSE 0 END) * 100.0 / COUNT(ScreeningID) AS DECIMAL(5,2)) AS MAM_Percentage

FROM Fact_Screenings;
GO
-- Check
SELECT * FROM [dbo].[vw_Overall_Malnutrition_Rates]
GO

-- 2. Geographic Analysis: Malnutrition by District

CREATE VIEW vw_District_Performance AS
SELECT 
    c.District,
    COUNT(f.ScreeningID) AS Total_Screenings,
    SUM(CASE WHEN f.Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) AS SAM_Cases,
    SUM(CASE WHEN f.Malnutrition_Status = 'MAM' THEN 1 ELSE 0 END) AS MAM_Cases,
    
    -- SAM Rate per district
    CAST(SUM(CASE WHEN f.Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) * 100.0 / COUNT(f.ScreeningID) AS DECIMAL(5,2)) AS SAM_Rate_Percent
FROM 
    Fact_Screenings f
JOIN 
    Dim_Clinic c ON f.ClinicID = c.ClinicID
GROUP BY 
    c.District;
GO

-- check
SELECT * FROM [dbo].[vw_District_Performance]
GO

-- 3. Temporal Trend: Monthly SAM Caseload
CREATE VIEW vw_Monthly_Trend AS
SELECT 
    YEAR(ScreeningDate) AS Screening_Year,
    MONTH(ScreeningDate) AS Screening_Month,
    -- Creates a clean string like "2025-01" for chronological sorting
    FORMAT(ScreeningDate, 'yyyy-MM') AS YearMonth,
    
    COUNT(ScreeningID) AS Total_Screenings,
    SUM(CASE WHEN Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) AS SAM_Cases,
    SUM(CASE WHEN Malnutrition_Status = 'MAM' THEN 1 ELSE 0 END) AS MAM_Cases
FROM 
    Fact_Screenings
GROUP BY 
    YEAR(ScreeningDate), 
    MONTH(ScreeningDate),
    FORMAT(ScreeningDate, 'yyyy-MM');
GO

-- check
SELECT * FROM [dbo].[vw_Monthly_Trend]
GO

-- 4. Demographic Analysis: Gender and Age Vulnerability

CREATE VIEW vw_Demographic_Vulnerability AS
SELECT 
    ch.Gender,
    -- Create age buckets
    CASE 
        WHEN f.AgeInMonths BETWEEN 6 AND 11 THEN '6-11 Months'
        WHEN f.AgeInMonths BETWEEN 12 AND 23 THEN '12-23 Months'
        WHEN f.AgeInMonths BETWEEN 24 AND 35 THEN '24-35 Months'
        WHEN f.AgeInMonths >= 36 THEN '36+ Months'
    END AS Age_Group,
    
    COUNT(f.ScreeningID) AS Total_Screenings,
    SUM(CASE WHEN f.Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) AS SAM_Cases,
    CAST(SUM(CASE WHEN f.Malnutrition_Status = 'SAM' THEN 1 ELSE 0 END) * 100.0 / COUNT(f.ScreeningID) AS DECIMAL(5,2)) AS SAM_Rate_Percent
FROM 
    Fact_Screenings f
JOIN 
    Dim_Child ch ON f.ChildID = ch.ChildID
GROUP BY 
    ch.Gender,
    CASE 
        WHEN f.AgeInMonths BETWEEN 6 AND 11 THEN '6-11 Months'
        WHEN f.AgeInMonths BETWEEN 12 AND 23 THEN '12-23 Months'
        WHEN f.AgeInMonths BETWEEN 24 AND 35 THEN '24-35 Months'
        WHEN f.AgeInMonths >= 36 THEN '36+ Months'
    END;
GO

-- check
SELECT * FROM [dbo].[vw_Demographic_Vulnerability]
GO