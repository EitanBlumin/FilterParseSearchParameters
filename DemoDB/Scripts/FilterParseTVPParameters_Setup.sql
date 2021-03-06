﻿/*
	Fully Parameterized Search Query
	--------------------------------
	
	Copyright Eitan Blumin (c) 2018; email: eitan@madeiradata.com
	You may use the contents of this SQL script or parts of it, modified or otherwise
	for any purpose that you wish (including commercial).
	Under the single condition that you include in the script
	this comment block unchanged, and the URL to the original source, which is:
	http://www.eitanblumin.com/
*/


/*
---------------- Tables ----------------

FilterTables
---------------

A logical group of available filter columns. Each group will represent a single database view (possibly de-normalized).
*/

IF OBJECT_ID('FilterTables') IS NOT NULL AND OBJECTPROPERTY(OBJECT_ID('FilterTables'), 'IsTable') = 1
	DROP TABLE FilterTables;
GO
CREATE TABLE FilterTables
(
	FilterTableAlias SYSNAME NOT NULL PRIMARY KEY,
	FilterTableName SYSNAME NOT NULL
)

-- Sample data
INSERT INTO FilterTables
(FilterTableAlias,FilterTableName)
VALUES
 ('Members','Operation.Members')
,('Session Events','dbo.VW_SessionEvents')
,('Invitations','dbo.VW_Invitations')

GO
/*

FilterOperators
-----------------

This table will contain the list of possible Operators and the template for each.
The templates use "placeholders" such as {Column} and {Parameter} which can later
be easily replaced with relevant values.
{Column}		= Placeholder for the column name to be filtered.
{Parameter}		= Placeholder for the local parameter that contains the filter data.

*/
IF OBJECT_ID('FilterOperators') IS NOT NULL AND OBJECTPROPERTY(OBJECT_ID('FilterOperators'), 'IsTable') = 1
	DROP TABLE FilterOperators;
GO
CREATE TABLE FilterOperators
(
	OperatorID INT PRIMARY KEY,
	IsMultiValue BIT NOT NULL,
	OperatorName VARCHAR(50) NOT NULL,
	OperatorTemplate VARCHAR(4000) NOT NULL
);
INSERT INTO FilterOperators
VALUES
 (1, 0, 'Contains', '{Column} LIKE ''%'' + {Parameter} + ''%''')
,(2, 0, 'NotContains', '{Column} NOT LIKE ''%'' + {Parameter} + ''%''')
,(3, 0, 'StartsWith', '{Column} LIKE {Parameter} + ''%''')
,(4, 0, 'EndsWith', '{Column} LIKE ''%'' + {Parameter}')
,(5, 0, 'GreaterThan', '{Column} > {Parameter}')
,(6, 0, 'GreaterOrEqual', '{Column} >= {Parameter}')
,(7, 0, 'LessThan', '{Column} < {Parameter}')
,(8, 0, 'LessOrEqual', '{Column} <= {Parameter}')
,(9, 0, 'Equals', '{Column} = {Parameter}')
,(10, 0, 'NotEquals', '{Column} <> {Parameter}')
,(11, 1, 'In', '{Column} IN (SELECT Value FROM {Parameter})')
,(12, 1, 'NotIn', '{Column} NOT IN (SELECT Value FROM {Parameter})')

GO
/*

FilterColumns
----------------

This table will map column names from our target table to an ID and a data type.
Using this table, the GUI can identify columns that can be filtered,
and later the database back-end will use the same table for parsing.

The field QueryForAvailableValues accepts a database query that must return 3 columns:
 [value] - Will be used for returning the actual value to be used in the Operator template
 [label] - Will be used for displaying the label to the front-end user
 [group] - If not NULL, will be used for grouping the values into option groups

*/
IF OBJECT_ID('FilterColumns') IS NOT NULL AND OBJECTPROPERTY(OBJECT_ID('FilterColumns'), 'IsTable') = 1
	DROP TABLE FilterColumns;
GO
CREATE TABLE FilterColumns
(
	ColumnID INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
	ColumnFilterTableAlias SYSNAME NOT NULL FOREIGN KEY REFERENCES FilterTables(FilterTableAlias) ON UPDATE CASCADE,
	ColumnRealName SYSNAME NOT NULL,
	ColumnSqlDataType VARCHAR(50) NOT NULL,
	ColumnDisplayName NVARCHAR(200) NULL,
	ColumnSortEnabled BIT NOT NULL,
	ColumnSupportedFilterOperators VARCHAR(100) NULL,
	QueryForAvailableValues VARCHAR(4000) NULL
);

-- Sample data
INSERT INTO FilterColumns
(ColumnFilterTableAlias,ColumnRealName,ColumnSqlDataType,ColumnDisplayName,ColumnSortEnabled,ColumnSupportedFilterOperators,QueryForAvailableValues)
VALUES
 ('Members', 'Id', 'int', 'Member Id', 1, NULL, NULL)
,('Members', 'Username', 'nvarchar(10)', 'User Name', 1, '1, 2, 3, 4, 9, 10', NULL)
,('Members', 'FirstName', 'nvarchar(20)', 'First Name', 1, '1, 2, 3, 4, 9, 10', NULL)
,('Members', 'LastName', 'nvarchar(20)', 'Last Name', 1, '1, 2, 3, 4, 9, 10', NULL)
,('Members', 'CountryId', 'tinyint', 'Country', 1, '9,10,11,12', 'SELECT Id AS [value], Name AS [label], NULL AS [group] FROM Lists.Countries ORDER BY 2')
,('Members', 'GenderID', 'tinyint', 'Gender', 1, '9,10,11', 'SELECT Id AS [value], Name AS [label], NULL AS [group] FROM Lists.Genders ORDER BY 2')
,('Members', 'SexualPreferenceId', 'tinyint', 'Sexual Preference', 1, '9,10,11', 'SELECT Id AS [value], Name AS [label], NULL AS [group] FROM Lists.Genders ORDER BY 2')
,('Members', 'BirthDate', 'date', 'BirthDate', 1, '5, 6, 7, 8, 9, 10', NULL)
,('Members', 'RegistrationDateTime', 'datetime', 'Registration Date and Time', 1, '5, 6, 7, 8, 9, 10', NULL)

GO
IF OBJECT_ID('dbo.FilterParseTVPParameters') IS NOT NULL
    DROP PROCEDURE dbo.FilterParseTVPParameters
GO
IF TYPE_ID('dbo.UDT_FilterParameters') IS NOT NULL
    DROP TYPE dbo.UDT_FilterParameters
GO
CREATE TYPE dbo.UDT_FilterParameters AS TABLE
(
	ParamIndex int NOT NULL,
	ColumnID int NOT NULL, 
	OperatorID int NOT NULL,
	[Value] nvarchar(max) NOT NULL

   -- See SQL Server Books Online for guidelines on determining appropriate bucket count for the index
   --, INDEX UDTIX_FilterParameters HASH (ParamIndex) WITH (BUCKET_COUNT = 30)
) --WITH (MEMORY_OPTIMIZED = ON)
GO
IF TYPE_ID('dbo.UDT_ColumnOrder') IS NOT NULL
    DROP TYPE dbo.UDT_ColumnOrder
GO
CREATE TYPE dbo.UDT_ColumnOrder AS TABLE
(
	ColumnOrdinal int NOT NULL,
	ColumnID int NOT NULL, 
	IsAscending bit NOT NULL

   -- See SQL Server Books Online for guidelines on determining appropriate bucket count for the index
   --,INDEX UDTIX_ColumnOrder HASH (ColumnOrdinal) WITH (BUCKET_COUNT = 10)
) --WITH (MEMORY_OPTIMIZED = ON)
GO
/*
	Fully Parameterized Search Query
	--------------------------------
	
	Copyright Eitan Blumin (c) 2018; email: eitan@madeiradata.com
	You may use the contents of this SQL script or parts of it, modified or otherwise
	for any purpose that you wish (including commercial).
	Under the single condition that you include in the script
	this comment block unchanged, and the URL to the original source, which is:
	http://www.eitanblumin.com/

--------------------------------
Example Usage:
--------------------------------
DECLARE @SQL NVARCHAR(MAX), @TVPParams dbo.UDT_FilterParameters, @TVPOrdering dbo.UDT_ColumnOrder

INSERT INTO @TVPParams
(ColumnID, OperatorID, [Value])
VALUES
(1, 11, N'2'),
(2, 11, N'RTCMLIVEDB3'),
(2, 11, N'TheOptionLiveDB'),
(3, 6, N'2018-11-11 15:00')

INSERT INTO @TVPOrdering
(ColumnOrdinal, ColumnID, IsAscending)
VALUES
(1, 11, 1),
(2, 5, 1)

EXEC dbo.FilterParseTVPParameters @SourceTableAlias = 'Members', @TVPParams = @TVPParams, @TVPOrdering = @TVPOrdering, @ParsedSQL = @SQL OUTPUT

PRINT @SQL

EXEC sp_executesql @SQL, N'@TVPParams dbo.UDT_FilterParametersas READONLY', @TVPParams

*/
CREATE PROCEDURE [dbo].[FilterParseTVPParameters]
	@SourceTableAlias	SYSNAME,				-- the alias of the table from FilterTables to be used as the source
	@TVPParams			dbo.UDT_FilterParameters READONLY,	-- the TVP definition of the parameter values
	@TVPOrdering		dbo.UDT_ColumnOrder READONLY,		-- the TVP definition of the column ordering (optional)
	@PageSize			INT = 9999,
	@Offset				INT = 1,
	@ParsedSQL			NVARCHAR(MAX) OUTPUT,	-- returns the parsed SQL command to be used for sp_executesql.
	@ForceRecompile		BIT = 1,				-- forces the query to do parameter sniffing using OPTION(RECOMPILE)
	@RowNumberColumn	SYSNAME = 'RowNumber',	-- you can optionally change the name of the RowNumber column used for pagination (to avoid collision with existing columns)
	@RunCommand			BIT = 0					-- determines whether to run the parsed command (otherwise just output the command w/o running it)
--WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN
--ATOMIC WITH(TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
SET XACT_ABORT ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
-- Init variables
DECLARE 
	@SourceTableName SYSNAME,
	@PageOrdering NVARCHAR(MAX),
	@FilterString NVARCHAR(MAX), 
	@FilterTablesString NVARCHAR(MAX), 
	@FilterParamInit NVARCHAR(4000)

SET @FilterString = N'';
SET @FilterTablesString = N'';

SELECT @SourceTableName = FilterTableName
FROM FilterTables
WHERE FilterTableAlias = @SourceTableAlias

IF @SourceTableName IS NULL
BEGIN
	RAISERROR(N'Table %s was not found in definitions',16,1,@SourceTableAlias);
	RETURN -1;
END

-- Prepare the ORDER BY clause (save in indexed temp table to ensure sort which might be distorted by the JOIN otherwise)
DECLARE @SortedColumns AS TABLE (ColumnRealName SYSNAME, IsAscending BIT, ColumnIndex BIGINT PRIMARY KEY);

INSERT INTO @SortedColumns
SELECT
	FilterColumns.ColumnRealName, Q.IsAscending, Q.ColumnIndex
FROM
(
	SELECT
		ColumnIndex			= ColumnOrdinal,
		OrderingColumnID	= ColumnID,
		IsAscending			= IsAscending
	FROM
		@TVPOrdering
) AS Q
JOIN
	FilterColumns
ON
	Q.OrderingColumnID = FilterColumns.ColumnID
INNER JOIN
	FilterTables
ON
	FilterColumns.ColumnFilterTableAlias = FilterTables.FilterTableAlias
WHERE
	FilterColumns.ColumnSortEnabled = 1
AND FilterColumns.ColumnFilterTableAlias = @SourceTableAlias

SELECT
	@PageOrdering = ISNULL(@PageOrdering + N', ',N'') + ColumnRealName + N' ' + CASE WHEN IsAscending = 1 THEN 'ASC' ELSE 'DESC' END
FROM @SortedColumns

IF @PageOrdering IS NULL
	SET @PageOrdering = '(SELECT NULL)'

-- Parse filtering
SELECT
	@FilterParamInit = ISNULL(@FilterParamInit, '') + N'
DECLARE @p' + ParamIndex +

		-- If Operator is multi-valued, declare local variable as a temporary table, to ensure strong-typing
		CASE WHEN FilterOperators.IsMultiValue = 1 THEN
			N' TABLE ([Value] ' + FilterColumns.ColumnSqlDataType + N');
			INSERT INTO @p' + ParamIndex + N'
			SELECT CONVERT(' + FilterColumns.ColumnSqlDataType + N', [value])
			FROM @TVPParams
			WHERE ParamIndex = ' + ParamIndex + N';
			'
		
		-- If Operator is single-valued, declare the local variable as a regular variable, to ensure strong-typing.
		ELSE
			N' ' + FilterColumns.ColumnSqlDataType + N';
			SELECT @p' + ParamIndex + N' = CONVERT(' + FilterColumns.ColumnSqlDataType + N', [value]) FROM @TVPParams WHERE ParamIndex = ' + ParamIndex + N';
			'
		END
		,
	-- Parse the Operator template by replacing the placeholders
	@FilterString = @FilterString + N'
	AND ' + REPLACE(
			REPLACE(
			FilterOperators.OperatorTemplate
			, '{Column}',FilterColumns.ColumnRealName)
			, '{Parameter}', '@p' + ParamIndex)
FROM
	(
		SELECT DISTINCT
			ParamIndex			= CONVERT(nvarchar(max), ParamIndex) COLLATE database_default,
			FilterColumnID		= ColumnId,
			FilterOperatorID	= OperatorID
		FROM
			@TVPParams
	) AS ParamValues
JOIN
	FilterColumns
ON
	ParamValues.FilterColumnID = FilterColumns.ColumnID
JOIN
	FilterOperators
ON
	ParamValues.FilterOperatorID = FilterOperators.OperatorID
INNER JOIN
	FilterTables
ON
	FilterColumns.ColumnFilterTableAlias = FilterTables.FilterTableAlias
WHERE
	FilterColumns.ColumnFilterTableAlias = @SourceTableAlias

-- Construct the final parsed SQL command
SET @ParsedSQL = ISNULL(@FilterParamInit, '') + N'
SELECT * FROM
(SELECT Main.*, ' + QUOTENAME(@RowNumberColumn) + N' = ROW_NUMBER() OVER( ORDER BY ' + @PageOrdering + N' )
FROM ' + @SourceTableName + N' AS Main
WHERE 1=1 ' + ISNULL(@FilterString,'') + N'
) AS Q
WHERE '+ QUOTENAME(@RowNumberColumn) + N' BETWEEN ' + CONVERT(nvarchar(50), @Offset) + N' AND ' + CONVERT(nvarchar(50), @Offset + @PageSize - 1) + N'
ORDER BY ' + QUOTENAME(@RowNumberColumn);

-- Optionally add RECOMPILE hint
IF @ForceRecompile = 1
	SET @ParsedSQL = @ParsedSQL + N'
OPTION (RECOMPILE)'

-- Optionally run the command
IF @RunCommand = 1
	EXEC sp_executesql @ParsedSQL, N'@TVPParams dbo.UDT_FilterParameters READONLY', @TVPParams
END
GO
