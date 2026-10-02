-- ============================================================
-- PetFinder – Analytical queries
-- Platform: Microsoft SQL Server (T-SQL)
-- ============================================================

-- 1. Shelters with more than two direct donations in the last year
--    (count, total, average, most recent donation)
SELECT
s.Name AS ShelterName,
addr.City,
addr.Country,
COUNT(d.DonationID) AS TotalDonations,
SUM(d.Amount) AS TotalAmount,
AVG(d.Amount) AS AverageAmount,
MAX(d.DonationDate) AS MostRecentDonation
FROM Shelters AS s
JOIN Donations AS d
ON s.ShelterID = d.ShelterID
JOIN Addresses AS addr
ON s.AddressID = addr.AddressID
WHERE d.DonationDate >= DATEADD(YEAR, -1, GETDATE())
GROUP BY s.ShelterID, s.Name, addr.City, addr.Country
HAVING COUNT(d.DonationID) > 2
ORDER BY TotalAmount DESC;

-- 2. Approved / pending adoption requests from the last year,
--    with days waiting since submission
SELECT ru.Name_First + ' ' + ru.Name_Last AS UserFullName,
    ru.Email,
    a.Name AS AnimalName, a.PetType, a.Breed,
    sh.Name AS ShelterName,
    ar.RequestDate, ar.DecisionStatus,
    DATEDIFF(DAY, ar.RequestDate, GETDATE()) AS DaysWaiting
FROM Registered_Users AS ru
JOIN Adoption_Requests AS ar ON ru.UserIP = ar.UserIP
JOIN Animals AS a ON ar.AnimalID = a.AnimalID
JOIN Shelters AS sh ON a.ShelterID = sh.ShelterID
WHERE ar.DecisionStatus IN ('Pending', 'Approved')
    AND ar.RequestDate >= CAST(DATEADD(YEAR, -1, GETDATE()) AS DATE)
ORDER BY ar.RequestDate DESC;

-- 3. Donations above the platform-wide average (scalar subquery),
--    with card type and target (shelter / animal / both)
SELECT
d.DonationID,
d.Amount,
d.DonationDate,
cc.CreditType,
s.Name AS ShelterName,
a.Name AS AnimalName
FROM Donations AS d
JOIN Credit_Cards AS cc
ON d.CC_CardNumber = cc.CC_CardNumber
LEFT JOIN Shelters AS s
ON d.ShelterID = s.ShelterID
LEFT JOIN Animals AS a
ON d.AnimalID = a.AnimalID
WHERE d.Amount > (
SELECT AVG(Amount)
FROM Donations
)
ORDER BY d.Amount DESC;

-- 4. Users active in all three funnel stages (search, favorites, adoption request)
--    Each activity table is pre-aggregated in a derived table to avoid row multiplication
SELECT ru.Name_First + ' ' + ru.Name_Last AS UserName,
    ru.Email,
    search_summary.TotalSearches,
    fav_summary.TotalFavorites,
    adopt_summary.TotalRequests,
    adopt_summary.ApprovedRequests
FROM Registered_Users AS ru
JOIN (
    SELECT UserIP, COUNT(*) AS TotalSearches
    FROM Searches
    GROUP BY UserIP
) AS search_summary ON ru.UserIP = search_summary.UserIP
JOIN (
    SELECT UserIP, COUNT(*) AS TotalFavorites
    FROM Favorites
    GROUP BY UserIP
) AS fav_summary ON ru.UserIP = fav_summary.UserIP
JOIN (
    SELECT UserIP,
           COUNT(*) AS TotalRequests,
           SUM(CASE WHEN DecisionStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedRequests
    FROM Adoption_Requests
    GROUP BY UserIP
) AS adopt_summary ON ru.UserIP = adopt_summary.UserIP
ORDER BY adopt_summary.TotalRequests DESC,
         search_summary.TotalSearches DESC;

-- 5. Window functions: RANK + running total of adoption requests within each pet type
SELECT
a.Name AS AnimalName,
a.PetType,
a.Breed,
a.Gender,
s.Name AS ShelterName,
COUNT(ar.RequestID) AS TotalRequests,
RANK() OVER (
PARTITION BY a.PetType
ORDER BY COUNT(ar.RequestID) DESC
) AS RankWithinPetType,
SUM(COUNT(ar.RequestID)) OVER (
PARTITION BY a.PetType
ORDER BY COUNT(ar.RequestID) DESC, a.AnimalID
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS RunningTotalWithinPetType,
SUM(COUNT(ar.RequestID)) OVER (
PARTITION BY a.PetType
) AS TotalRequestsForPetType
FROM Animals AS a
JOIN Shelters AS s
ON a.ShelterID = s.ShelterID
LEFT JOIN Adoption_Requests AS ar
ON a.AnimalID = ar.AnimalID
GROUP BY
a.AnimalID,
a.Name,
a.PetType,
a.Breed,
a.Gender,
s.Name
ORDER BY a.PetType, RankWithinPetType, a.AnimalID;

-- 6. Window functions: LAG (change vs. previous donation per user) + NTILE(4) quartiles
SELECT ru.Name_First + ' ' + ru.Name_Last AS UserName,
    d.DonationDate, d.DonationID, d.Amount AS CurrentDonation,
    LAG(d.Amount) OVER (PARTITION BY ru.UserIP ORDER BY d.DonationDate, d.DonationID) AS PreviousDonation,
    d.Amount - LAG(d.Amount) OVER (PARTITION BY ru.UserIP ORDER BY d.DonationDate, d.DonationID) AS ChangeFromPrevious,
    NTILE(4) OVER (ORDER BY d.Amount DESC) AS DonationAmountQuartile
FROM Donations AS d
JOIN Credit_Cards AS cc ON d.CC_CardNumber = cc.CC_CardNumber
JOIN Registered_Users AS ru ON ru.CC_CardNumber = cc.CC_CardNumber
ORDER BY ru.UserIP, d.DonationDate, d.DonationID;

-- 7. Adoption-funnel engagement report: multi-step CTE + correlated subquery + RANK
WITH UserSearchActivity AS (
    SELECT UserIP,
           COUNT(*) AS TotalSearches,
           MIN(SearchDT) AS FirstSearchDate,
           MAX(SearchDT) AS LastSearchDate,
           COUNT(DISTINCT Location) AS UniqueLocationsSearched
    FROM Searches
    GROUP BY UserIP
),
UserRequestOutcomes AS (
    SELECT UserIP,
           COUNT(*) AS TotalRequests,
           SUM(CASE WHEN DecisionStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedRequests,
           SUM(CASE WHEN DecisionStatus = 'Pending' THEN 1 ELSE 0 END) AS PendingRequests
    FROM Adoption_Requests
    GROUP BY UserIP
),
UserFunnelMetrics AS (
    SELECT
           usa.UserIP, usa.TotalSearches,
           usa.FirstSearchDate, usa.LastSearchDate,
           usa.UniqueLocationsSearched,
           ISNULL(uro.TotalRequests, 0) AS TotalRequests,
           ISNULL(uro.ApprovedRequests, 0) AS ApprovedRequests,
           ISNULL(uro.PendingRequests, 0) AS PendingRequests,
           CAST(ISNULL(uro.TotalRequests, 0) AS FLOAT) / usa.TotalSearches * 100 AS RequestsPer100Searches,
           DATEDIFF(DAY, usa.FirstSearchDate, usa.LastSearchDate) AS DaysActive
    FROM UserSearchActivity AS usa
    LEFT JOIN UserRequestOutcomes AS uro ON usa.UserIP = uro.UserIP
)

SELECT ru.Name_First + ' ' + ru.Name_Last AS UserName,
       ru.Email,
       ufm.TotalSearches,

       (SELECT COUNT(*) FROM Matching_Tests mt WHERE mt.UserIP = ru.UserIP) AS TotalTests,

       ufm.TotalRequests,
       ufm.ApprovedRequests,
       ufm.PendingRequests,
       ufm.UniqueLocationsSearched,
       ufm.DaysActive,
       CAST(ufm.RequestsPer100Searches AS DECIMAL(7,2)) AS RequestsPer100Searches,
       ufm.FirstSearchDate,
       ufm.LastSearchDate,
       RANK() OVER (ORDER BY ufm.TotalRequests DESC, ufm.TotalSearches DESC) AS AdoptionIntentRank
FROM Registered_Users AS ru
JOIN UserFunnelMetrics AS ufm ON ru.UserIP = ufm.UserIP
ORDER BY AdoptionIntentRank;

-- 8. PIVOT: adoption-request matrix by shelter x pet type (stored procedure)
CREATE PROCEDURE usp_GenerateAdoptionMatrixReport
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ShelterName, [Dogs], [Cats], [Rabbits], [Birds], [Small&Furry]
    FROM (
        SELECT
            sh.Name AS ShelterName,
            a.PetType,
            ar.RequestID
        FROM Shelters AS sh
        JOIN Animals AS a ON sh.ShelterID = a.ShelterID
        JOIN Adoption_Requests AS ar ON a.AnimalID = ar.AnimalID
    ) AS SourceData
    PIVOT (
        COUNT(RequestID)
        FOR PetType IN ([Dogs], [Cats], [Rabbits], [Birds], [Small&Furry])
    ) AS PivotTable
    ORDER BY ShelterName;
END;
GO
-- Run it
EXEC usp_GenerateAdoptionMatrixReport;
