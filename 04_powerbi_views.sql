-- ============================================================
-- PetFinder – Reporting views feeding the Power BI dashboards
-- Platform: Microsoft SQL Server (T-SQL)
-- ============================================================

-- Fundraising & Marketing report
CREATE OR ALTER VIEW vw_DonationMarketingAnalysis AS
SELECT
    D.DonationID,
    D.Amount,
    D.DonationDate,

    CASE
        WHEN D.AnimalID IS NOT NULL THEN 'Specific Animal'
        WHEN D.ShelterID IS NOT NULL THEN 'General Shelter'
    END AS TargetType,

    ISNULL(A.PetType, 'N/A (Shelter Donation)') AS TargetPetType,

    ISNULL(A.Breed, 'N/A (Shelter Donation)') AS TargetBreed,

    ISNULL(A.Name, S.Name) AS TargetName,

    ISNULL(Addr.Country, 'Unknown/Guest') AS DonorCountry,
    ISNULL(Addr.City, 'Unknown/Guest') AS DonorCity,

    CASE
        WHEN D.TestUserIP IS NOT NULL THEN 'After Matching Test'
        WHEN D.SearchUserIP IS NOT NULL THEN 'After Search'
        ELSE 'Direct Donation'
    END AS DonationSource

FROM
    Donations D
    LEFT JOIN Animals A ON D.AnimalID = A.AnimalID
    LEFT JOIN Shelters S ON D.ShelterID = S.ShelterID
    LEFT JOIN Registered_Users RU ON D.CC_CardNumber = RU.CC_CardNumber
    LEFT JOIN Addresses Addr ON RU.AddressID = Addr.AddressID;
GO

-- Management dashboard: adoption requests
CREATE VIEW vw_PowerBI_AdoptionRequests AS
SELECT
    AR.RequestID,
    AR.RequestDate,
    AR.DecisionStatus,
    CASE
        WHEN AR.SearchUserIP IS NOT NULL THEN 'Search'
        ELSE 'Matching Test'
    END AS RequestSource,
    DATEDIFF(DAY, COALESCE(AR.SearchDT, AR.TestDT), AR.RequestDate) AS DaysToRequest,
    A.AnimalID,
    A.PetType,
    A.Breed,
    S.ShelterID,
    S.Name AS ShelterName,
    AR.UserIP AS RequestingUserIP,
    ADDR.Country AS AdopterCountry,
    ADDR.City AS AdopterCity
FROM Adoption_Requests AR
LEFT JOIN Animals A ON AR.AnimalID = A.AnimalID
LEFT JOIN Shelters S ON A.ShelterID = S.ShelterID
LEFT JOIN Registered_Users RU ON AR.UserIP = RU.UserIP
LEFT JOIN Addresses ADDR ON RU.AddressID = ADDR.AddressID;
GO

-- Management dashboard: KPI cards
CREATE VIEW vw_PowerBI_SystemKPIs AS
SELECT
    (SELECT COUNT(*) FROM Users) AS Total_Users,
    (SELECT COUNT(*) FROM Registered_Users) AS Total_Registered_Users,
    (SELECT COUNT(*) FROM Adoption_Requests) AS Total_Adoption_Requests,
    (SELECT COUNT(*) FROM Animals) AS Total_Animals;
GO
