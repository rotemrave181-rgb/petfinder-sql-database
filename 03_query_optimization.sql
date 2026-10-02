-- ============================================================
-- PetFinder – Query optimisation (reviewed against execution plans)
-- Platform: Microsoft SQL Server (T-SQL)
-- ============================================================

-- Query 1 optimised: early aggregation in a CTE on Donations (by ShelterID) before joining
--   Estimated relative cost in the execution plan: 60% -> 40%
WITH ShelterDonations AS (
    SELECT
        ShelterID,
        COUNT(DonationID) AS TotalDonations,
        SUM(Amount) AS TotalAmount,
        AVG(Amount) AS AverageAmount,
        MAX(DonationDate) AS MostRecentDonation
    FROM Donations
    WHERE DonationDate >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY ShelterID
    HAVING COUNT(DonationID) > 2
)
SELECT
    s.Name AS ShelterName,
    addr.City,
    addr.Country,
    sd.TotalDonations,
    sd.TotalAmount,
    sd.AverageAmount,
    sd.MostRecentDonation
FROM ShelterDonations sd
JOIN Shelters s
    ON sd.ShelterID = s.ShelterID
JOIN Addresses addr
    ON s.AddressID = addr.AddressID
ORDER BY sd.TotalAmount DESC;

-- Query 3 rewritten: pre-compute the average into a variable to separate aggregation from retrieval
--   Result: no meaningful runtime gain at this data volume (SQL Server already optimised the
--   original subquery), but a clearer, more maintainable structure
DECLARE @AvgDonation DECIMAL(10,2);

SELECT @AvgDonation = AVG(Amount)
FROM Donations;

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
WHERE d.Amount > @AvgDonation
ORDER BY d.Amount DESC;
