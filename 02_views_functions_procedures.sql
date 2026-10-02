-- ============================================================
-- PetFinder – Views, functions, trigger and stored procedures
-- Platform: Microsoft SQL Server (T-SQL)
-- ============================================================

-- VIEW: animals currently available for adoption (excludes animals with an approved request)
CREATE VIEW vw_AvailableAnimals AS
SELECT
    a.AnimalID,
    a.Name AS AnimalName,
    a.PetType,
    a.Breed,
    a.Gender,
    s.ShelterID,
    s.Name AS ShelterName,
    s.Phone AS ShelterPhone,
    addr.City,
    addr.Country
FROM Animals AS a
JOIN Shelters AS s ON a.ShelterID = s.ShelterID
JOIN Addresses AS addr ON s.AddressID = addr.AddressID
WHERE a.AnimalID NOT IN (
SELECT AnimalID FROM Adoption_Requests WHERE DecisionStatus = 'Approved' );
GO

-- SCALAR FUNCTION: total direct donations received by a shelter
CREATE FUNCTION fn_GetShelterTotalDonations (@ShelterID INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @Total DECIMAL(10,2)

    SELECT @Total = ISNULL(SUM(Amount), 0)
    FROM Donations
    WHERE ShelterID = @ShelterID

    RETURN @Total
END
GO

-- Example usage
SELECT
    s.Name AS ShelterName,
    dbo.fn_GetShelterTotalDonations(s.ShelterID) AS TotalDonationsReceived
FROM Shelters AS s
ORDER BY TotalDonationsReceived DESC;

-- TABLE-VALUED FUNCTION: available animals filtered by pet type (built on the view)
CREATE FUNCTION fn_GetAnimalsByPetType (@PetType VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    SELECT AnimalID, AnimalName, Breed, Gender,
           ShelterName, ShelterPhone, City, Country
    FROM vw_AvailableAnimals
    WHERE PetType = @PetType
);
GO

-- Example usage
SELECT *
FROM fn_GetAnimalsByPetType('Dogs')
ORDER BY ShelterName;

-- TRIGGER: keep Shelters.TotalDonationsReceived in sync on INSERT / UPDATE / DELETE
-- Step 1 – add the column
ALTER TABLE Shelters
ADD TotalDonationsReceived DECIMAL(10,2) DEFAULT 0;
GO

-- Step 2 – initialise existing rows
UPDATE Shelters
SET TotalDonationsReceived = (
    SELECT ISNULL(SUM(Amount), 0)
    FROM Donations
    WHERE ShelterID = Shelters.ShelterID
);
GO

-- Step 3 – the trigger
CREATE TRIGGER trg_UpdateShelterDonations
ON Donations
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    UPDATE Shelters
    SET TotalDonationsReceived = (
        SELECT ISNULL(SUM(Amount), 0)
        FROM Donations
        WHERE ShelterID = Shelters.ShelterID
    )
    WHERE ShelterID IN (
        SELECT ShelterID FROM inserted WHERE ShelterID IS NOT NULL
        UNION
        SELECT ShelterID FROM deleted WHERE ShelterID IS NOT NULL
    )
END
GO

-- STORED PROCEDURE: process an adoption decision (validate, check existence, update, return summary)
CREATE PROCEDURE usp_ProcessAdoptionDecision
@RequestID INT,
@NewStatus VARCHAR(10)
AS
BEGIN
-- Step 1: Validate the status value
IF @NewStatus NOT IN ('Approved', 'Rejected', 'Pending')
BEGIN
PRINT 'Error: Status must be Approved, Rejected, or Pending.';
RETURN;
END;

-- Step 2: Check the request exists
IF NOT EXISTS (
SELECT 1
FROM Adoption_Requests
WHERE RequestID = @RequestID
)
BEGIN
PRINT 'Error: Adoption request not found.';
RETURN;
END;

-- Step 3: Update the decision status
UPDATE Adoption_Requests
SET DecisionStatus = @NewStatus
WHERE RequestID = @RequestID;

-- Step 4: Return summary of the updated request
SELECT
ar.RequestID,
ar.DecisionStatus,
ar.RequestDate,
a.Name AS AnimalName,
a.PetType,
sh.Name AS ShelterName,
ru.Name_First + ' ' + ru.Name_Last AS AdopterName,
ru.Email AS AdopterEmail
FROM Adoption_Requests AS ar
JOIN Animals AS a ON ar.AnimalID = a.AnimalID
JOIN Shelters AS sh ON a.ShelterID = sh.ShelterID
JOIN Registered_Users AS ru ON ar.UserIP = ru.UserIP
WHERE ar.RequestID = @RequestID;
END;
GO

EXEC usp_ProcessAdoptionDecision
    @RequestID = 3,
    @NewStatus = 'Approved';


-- STORED PROCEDURE with TRY...CATCH + transaction: register a donation (and a new card if needed) atomically
CREATE PROCEDURE usp_SafeRegisterDonationWithNewCard
    @Amount DECIMAL(10,2),
    @DonationDate DATE,
    @CC_CardNumber VARCHAR(20),
    @CreditType VARCHAR(50),
    @CC_Expiration DATE,
    @CC_CVV VARCHAR(4),
    @ShelterID INT = NULL,
    @AnimalID INT = NULL,
    @SearchUserIP VARCHAR(45) = NULL,
    @SearchDT DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @CreditType NOT IN ('VISA', 'MasterCard', 'AmericanExpress', 'JCB', 'UnionPay-CreditCard')
        BEGIN
            THROW 51000, 'Transaction Failed: Invalid or unsupported credit card type.', 1;
        END;

        IF NOT EXISTS (SELECT 1 FROM Credit_Cards WHERE CC_CardNumber = @CC_CardNumber)
        BEGIN
            INSERT INTO Credit_Cards (CC_CardNumber, CreditType, CC_Expiration, CC_CVV)
            VALUES (@CC_CardNumber, @CreditType, @CC_Expiration, @CC_CVV);
        END;

        IF @ShelterID IS NULL AND @AnimalID IS NULL
        BEGIN
            THROW 52000, 'Transaction Failed: A donation must target either a specific Shelter or a specific Animal.', 1;
        END;

        DECLARE @NewDonationID INT;
        SELECT @NewDonationID = ISNULL(MAX(DonationID), 0) + 1 FROM Donations;

        INSERT INTO Donations (DonationID, Amount, DonationDate, CC_CardNumber, ShelterID, AnimalID, SearchUserIP, SearchDT)
        VALUES (@NewDonationID, @Amount, @DonationDate, @CC_CardNumber, @ShelterID, @AnimalID, @SearchUserIP, @SearchDT);

        COMMIT TRANSACTION;
        PRINT 'The donation and credit card were registered successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'Transaction rolled back safely due to an error.';
        END;
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage,
            ERROR_LINE() AS ErrorLine;
    END CATCH;
END;
GO

-- Example call (dummy test values only)
EXEC usp_SafeRegisterDonationWithNewCard
    @Amount = 350.00,
    @DonationDate = '2026/06/24',
    @CC_CardNumber = '4580123456789012',
    @CreditType = 'VISA',
    @CC_Expiration = '2029/08/01',
    @CC_CVV = '123',
    @ShelterID = 1,
    @AnimalID = NULL,
    @SearchUserIP = NULL,
    @SearchDT = NULL;

