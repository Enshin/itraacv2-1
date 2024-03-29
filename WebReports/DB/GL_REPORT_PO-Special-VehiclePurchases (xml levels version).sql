USE [iTRAAC_Reports]
GO
/****** Object:  StoredProcedure [GL_REPORT_PO-Special-VehiclePurchases]    Script Date: 04/06/2012 12:34:28 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [GL_REPORT_PO-Special-VehiclePurchases]
@TaxOfficeName VARCHAR(100) = NULL,
@BeginDate DATETIME,
@EndDate DATETIME,
@Output XML = NULL OUT
AS BEGIN

-- gather the data first so we hit the best join/index optimization
-- spreading the joins out into the nested XML structure can definitely influence the query optimizer's chosen approach

-- first get all the hits for the specified office... 
SELECT
  --o.TaxOfficeId, O.TaxOfficeName, 
  tf.TaxFormId, TF.OrderNumber, convert(varchar, TFP.PurchaseDate, 0) as PurchaseDate, 
  c.ClientId, C.CCode, C.LName, C.FName, ISNULL(C.MI,'') AS MI, 
  CONVERT(VARCHAR, CONVERT(money, PPO.TotalCost), 1) + CASE PPO.CurrencyUsed WHEN 1 THEN ' USD' WHEN 2 THEN ' EUR' ELSE ' ???' END AS TotalCost,
  r.RowId as RemarkRowId,
  CASE R.RemType
    WHEN 3 THEN 'VIN'
    WHEN 7 THEN 'Make'
    WHEN 8 THEN 'Model'
    WHEN 9 THEN 'Year'
    ELSE 'Comments' end as RemarkType,
  CASE R.Remarks WHEN '!init!' THEN '<BLANK>' ELSE R.Remarks END AS Remark
INTO #t
FROM ITRAAC.dbo.tblTaxForms TF 
JOIN ITRAAC.dbo.tblTaxFormPackages TFP ON TFP.PackageID = TF.PackageID
JOIN ITRAAC.dbo.tblPPOData PPO ON PPO.TaxFormID=TF.TaxFormID
JOIN ITRAAC.dbo.tblRemarks R ON R.RowID=TF.TaxFormID
JOIN ITRAAC.dbo.tblTaxFormAgents A ON A.AgentID=TFP.AgentID 
JOIN ITRAAC.dbo.tblTaxOffices O ON O.TaxOfficeID=A.TaxOfficeID 
JOIN ITRAAC.dbo.tblClients C ON C.ClientID=TFP.ClientID
WHERE TF.TransTypeID=31 AND R.RemType IN (3,7,8,9) --31 is vehicle purchase 
AND (@TaxOfficeName IS NULL OR O.TaxOfficeName = @TaxOfficeName)
AND TFP.PurchaseDate BETWEEN @BeginDate AND @EndDate

-- but then go add all the hits in OTHER offices for the SAME CUSTOMER... so we can see if they're being naughty across offices
insert #t
select
  --o.TaxOfficeId, O.TaxOfficeName, 
  tf.TaxFormId, TF.OrderNumber, convert(varchar, TFP.PurchaseDate, 0) as PurchaseDate, 
  c.ClientId, C.CCode, C.LName, C.FName, ISNULL(C.MI, '') AS MI, 
  CONVERT(VARCHAR, CONVERT(money, PPO.TotalCost), 1) + CASE PPO.CurrencyUsed WHEN 1 THEN ' USD' WHEN 2 THEN ' EUR' ELSE ' ???' END AS TotalCost,
  r.RowId as RemarkRowId,
  CASE R.RemType
    WHEN 3 THEN 'VIN'
    WHEN 7 THEN 'Make'
    WHEN 8 THEN 'Model'
    WHEN 9 THEN 'Year'
    ELSE 'Comments' end as RemarkType,
  CASE R.Remarks WHEN '!init!' THEN '<BLANK>' ELSE R.Remarks END AS Remark
FROM ITRAAC.dbo.tblTaxForms TF 
JOIN ITRAAC.dbo.tblTaxFormPackages TFP ON TFP.PackageID = TF.PackageID
JOIN ITRAAC.dbo.tblPPOData PPO ON PPO.TaxFormID=TF.TaxFormID
JOIN ITRAAC.dbo.tblRemarks R ON R.RowID=TF.TaxFormID
--JOIN ITRAAC.dbo.tblTaxFormAgents A ON A.AgentID=TFP.AgentID 
--JOIN ITRAAC.dbo.tblTaxOffices O ON O.TaxOfficeID=A.TaxOfficeID 
JOIN ITRAAC.dbo.tblClients C ON C.ClientID=TFP.ClientID
WHERE TF.TransTypeID=31 AND R.RemType IN (3,7,8,9) --31 is vehicle purchase 
--(vehicles are rare enough per person that let's just open this up to full history) AND TFP.PurchaseDate BETWEEN @BeginDate AND @EndDate
and exists(select 1 from #t cust where cust.ClientId = c.ClientId)
and not exists(select 1 from #t form where form.TaxFormId = tf.TaxFormId)
;

-- return results in an xml hierarchy
-- this will then get xsl-transformed into html table at the web server tier

-- interesting annoyance... when i tried to use the trusty "concat" CLR aggregate, i'd get a syntax error on the delimiter param
--    my best guess is that this is a very esoteric t-sql parser bug... i can imagine the pivot syntax would be particularly complex to digest
--    most readily available fix would be to build the CLR library with a "concat_no_delim()" alternative
--    for now i don't think we're missing much since comments are rare

--Customer as the top level... 
SET @Output = (
SELECT
  COUNT(DISTINCT OrderNumber) AS [@Count], CCode AS [@CCode], LName AS [@LName], FName AS [@Fname], MI AS [@MI], 
  
  -- PO next level down
  (SELECT 
    OrderNumber AS [@OrderNumber], PurchaseDate AS [@PurchaseDate], TotalCost AS [@TotalCost],
    VIN AS [@VIN], Make AS [@Make], Model AS [@Model], [Year] AS [@Year], Comments AS [@Comments]
    FROM #t form
    JOIN (
      -- pivot vehicle detail rows as columns tacked on the PO level record 
      SELECT RemarkRowID AS TaxFormId, VIN, Make, Model, [Year], Comments
      FROM ( SELECT RemarkRowID, RemarkType, Remark FROM #t ) 
        AS pivsource
      PIVOT ( MAX(Remark) FOR RemarkType IN ([VIN], [Make], [Model], [Year], [Comments]) )
        AS pivresult
    ) remarks ON remarks.TaxFormId = form.TaxFormId
    WHERE form.ClientId = cust.ClientId
    GROUP BY
      form.TaxFormID, OrderNumber, PurchaseDate, TotalCost,
      VIN, Make, Model, [Year], Comments
    ORDER BY PurchaseDate
    FOR XML PATH('PO'), TYPE
  )

FROM #t AS cust
GROUP BY ClientId, CCode, LName, FName, MI
ORDER BY COUNT(DISTINCT OrderNumber) desc, CCode, LName
FOR XML PATH('Customer'), ROOT ('Report'), TYPE
)

DROP TABLE #t

END
