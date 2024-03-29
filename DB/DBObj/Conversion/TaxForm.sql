
use itraac
go

SET NUMERIC_ROUNDABORT OFF
GO
SET ANSI_PADDING, ANSI_WARNINGS, CONCAT_NULL_YIELDS_NULL, ARITHABORT, QUOTED_IDENTIFIER, ANSI_NULLS ON
GO
SET XACT_ABORT ON
GO

/*
-- delete all indexes off the primary tables (except for primary keys)
declare @RETURN_VALUE int
declare @command1 nvarchar(2000)
set @command1 = 'DECLARE @indexName NVARCHAR(128)'
set @command1 = @command1 + ' DECLARE @dropIndexSql NVARCHAR(4000), @uniqueconstraint bit'
set @command1 = @command1 + ' DECLARE tableIndexes CURSOR FAST_FORWARD FOR'
set @command1 = @command1 + '   SELECT name, is_unique_constraint FROM sys.indexes'
set @command1 = @command1 + '   WHERE object_id = OBJECT_ID(''?'') AND index_id > 0 AND index_id < 255 AND is_primary_key = 0'
set @command1 = @command1 + '   ORDER BY index_id DESC'
set @command1 = @command1 + ' OPEN tableIndexes'
set @command1 = @command1 + ' WHILE (1=1) BEGIN'
set @command1 = @command1 + '   FETCH NEXT FROM tableIndexes INTO @indexName, @uniqueconstraint'
set @command1 = @command1 + '   if (@@fetch_status <> 0) BREAK'
set @command1 = @command1 + '   if (@uniqueconstraint = 1) set @dropIndexSql = ''ALTER TABLE ? DROP CONSTRAINT '' + @indexName + '''''
set @command1 = @command1 + '   else SET @dropIndexSql = ''DROP INDEX ?.'' + @indexName + '''''
set @command1 = @command1 + '   EXEC sp_executesql @dropIndexSql'
set @command1 = @command1 + '   print @dropIndexSql'
set @command1 = @command1 + ' END'
set @command1 = @command1 + ' DEALLOCATE tableIndexes'
exec @RETURN_VALUE = sp_MSforeachtable @command1=@command1, @whereand = "and o.name in ('tblClients', 'tblPPOData', 'tblTaxFormPackages', 'tblTaxForms', 'tblTaxOffices')"
*/

/*************** tblTaxForms */
ALTER TABLE tblTaxForms ALTER COLUMN RowGUID DROP ROWGUIDCOL

ALTER TABLE tblTaxForms add PackageGUID uniqueidentifier NULL -- replaces PackageID
ALTER TABLE tblTaxForms add GoodServiceGUID uniqueidentifier NULL -- replaces GooodsServicesID
ALTER TABLE tblTaxForms add VendorGUID uniqueidentifier NULL -- replaces VendorID
ALTER TABLE tblTaxForms add ReturnUserGUID uniqueidentifier NULL -- replaces RetAgentID
ALTER TABLE tblTaxForms add FileUserGUID uniqueidentifier NULL -- replaces FileUserGUID
ALTER TABLE tblTaxForms add UsedDate datetime NULL -- finally!
ALTER TABLE tblTaxForms add ReturnedDate datetime NULL -- finally!
ALTER TABLE tblTaxForms add FiledDate datetime NULL -- finally!
ALTER TABLE tblTaxForms add RowVersion timestamp NOT NULL -- might come in handy
ALTER TABLE tblTaxForms add LocationCode VARCHAR(4) NOT NULL DEFAULT('CUST') -- to finally support LOST & 'incomplete, returned to CUST', etc.
ALTER TABLE tblTaxForms add Incomplete BIT NOT NULL DEFAULT(0) -- finally!

--can't do this yet, V1 blows up on NULL: ALTER TABLE tblTaxForms ALTER COLUMN TransTypeID int not NULL
ALTER TABLE tblTaxForms ALTER COLUMN GooodsServicesID int NULL
ALTER TABLE tblTaxForms ALTER COLUMN VendorID int NULL
ALTER TABLE tblTaxForms ALTER COLUMN RowGUID uniqueidentifier NOT NULL
ALTER TABLE tblTaxForms DROP CONSTRAINT DF_tblTaxForms_RowGUID
ALTER TABLE tblTaxForms ADD CONSTRAINT DF_tblTaxForms_RowGUID DEFAULT (NEWSEQUENTIALID()) FOR RowGUID
ALTER TABLE tblTaxForms ALTER COLUMN RetAgentID int NULL
ALTER TABLE tblTaxForms ALTER COLUMN FileAgentID INT NULL
ALTER TABLE tblTaxForms ADD CONSTRAINT DF_tblTaxForms_StatusFlags DEFAULT (0) FOR StatusFlags


DROP INDEX tblTaxForms.ix_ReturnedDate
DROP INDEX tblTaxForms.ix_FiledDate
--CREATE NONCLUSTERED INDEX ix_ReturnedDate ON tblTaxForms (ReturnedDate) INCLUDE (RowGUID, OrderNumber, StatusFlags, FiledDate) --both of these are for DailyActivity_s
--CREATE NONCLUSTERED INDEX ix_FiledDate ON tblTaxForms (FiledDate) INCLUDE (RowGUID, PackageGUID, OrderNumber, StatusFlags, ReturnedDate) --both of these are for DailyActivity_s
CREATE NONCLUSTERED INDEX ix_ReturnedDate ON tblTaxForms (ReturnedDate, PackageGUID) 
CREATE NONCLUSTERED INDEX ix_FiledDate ON tblTaxForms (FiledDate, PackageGUID) 


DROP INDEX tblTaxForms.idx_clustered
DROP INDEX tblTaxForms.ix_PackageGUID
CREATE CLUSTERED INDEX ix_PackageGUID ON tblTaxForms (PackageGUID, RowGUID) --TODO: 
create index ix_PackageID on tblTaxForms (PackageID, TaxFormID) 

--ALTER TABLE tblTaxForms WITH CHECK ADD CONSTRAINT FK_tblTaxForms_tblTaxFormPackages FOREIGN KEY(PackageGUID) REFERENCES tblTaxFormPackages (RowGUID)

DROP INDEX tblTaxForms.ix_RowGUID
CREATE UNIQUE INDEX ix_TaxFormGUID ON tblTaxForms (RowGUID)
CREATE UNIQUE INDEX ix_TaxFormID ON tblTaxForms (TaxFormID)

CREATE INDEX ix_TransactionTypeID ON tblTaxForms (TransTypeID) INCLUDE (PackageGUID) 
DROP INDEX tblTaxForms.ix_CtrlNumber
CREATE INDEX ix_CtrlNumber ON tblTaxForms (CtrlNumber) INCLUDE (PackageGUID) --for TaxForms_search 
CREATE INDEX ix_StatusFlags ON tblTaxForms (StatusFlags) INCLUDE (PackageGUID) 

/***** HUGE******/
-- see "Conversion\One Time Data Cleanups\TaxForm - Duplicate OrderNumber Fix.sql"
-- DROP INDEX tblTaxForms.ix_ordernumber
CREATE UNIQUE INDEX ix_OrderNumber ON tblTaxForms (OrderNumber, CtrlNumber) -- used for determining latest max CtrlNumber/OrderNumber in TaxFormPackage_new

-- future - OrderNumber should be a computed field
-- probably the only remaining physical column to add is FiscalYear

------ _ -------------------------------- _ ---------- _ ----- _ ----------------------------------- _ -----
--    / \      ____   _       _____      / \          / /     | |      _   _  _____           __    | |  
--   / ^ \    / __ \ | |     |  __ \    / ^ \        / /      | |     | \ | ||  ___|\        / /    | |  
--  /_/ \_\  | |  | || |     | |  | |  /_/ \_\      / /     __| |__   |  \| || |__ \ \  /\  / /   __| |__
--    | |    | |  | || |     | |  | |    | |       / /      \ \ / /   |     ||  __| \ \/  \/ /    \ \ / /
--    | |    | |__| || |____ | |__| |    | |      / /        \ V /    | |\  || |____ \  /\  /      \ V / 
--    |_|     \____/ |______||_____/     |_|     /_/          \_/     |_| \_||______| \/  \/        \_/  
------------------------------------------------------------------------------------------------------------

