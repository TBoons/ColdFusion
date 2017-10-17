<cfcomponent extends="boltAppRoot.cfc.obc" >
	<cffunction name="init" >
		<cfargument name="dsn" type="string" required="false" default="#application.dsn#" />
		<cfscript>
			variables.dsn = arguments.dsn;
			variables.strTelogisUsername = structKeyExists(application,'strTelogisUsername') ? application.strTelogisUsername : '';
			variables.strTelogisPassword = structKeyExists(application,'strTelogisPassword') ? application.strTelogisPassword : '';
			variables.strTelogisToken = structKeyExists(application,'strTelogisToken') ? application.strTelogisToken : '';
			variables.strTelogisURL = structKeyExists(application,'strTelogisURL') ? application.strTelogisURL : '';
			variables.telogisToken = getTelogisToken();
			variables.forceAssignment = true;

			return this;
		</cfscript>
	</cffunction>

	<cffunction name="breadcrumbs" returntype="void" >
		<cfscript>
			var lastTransactionTime = getTransaction( 'BREADCRUMBS' );
			var maxBreadCrumbs = 300;
			var breadcrumbsImported = 0;
			if ( !isDate( lastTransactionTime ) ){
				lastTransactionTime = '1990/1/1 00:00:00'; //Find Transaction from LONG ago.
			}

			var lastBreadcrumb = formatTelogisDateTime( lastTransactionTime );

			var parms = {
				'template': getTemplateId('BREADCRUMBS').templateId
				,'TimeStart'= lastBreadcrumb
			};

			var aryBreadcrumbs = [];
			var objResults = callTemplate(
				params: parms
			);

			if ( !structIsEmpty( objResults ) ){
				//Loops over Structure. The Name of the structure can change. This should always be just one item.

				//This is the array of breadcrumbs
				var breadcrumbs = objResults.TableEntry;

				if ( arrayLen( breadcrumbs ) ){

					for ( var ii IN breadcrumbs ){
						breadcrumbsImported++;
						if ( breadcrumbsImported > maxBreadCrumbs ){
							break;
						}
						var lastGPSTime = ii.time; //Find the last timestamp
						var intEquipmentId = getTruck( trim( ii.tag ) );

						//Data parse from telogis
						var speed = int( ii.speed );
						var heading = listGetAt( ii.heading, 1, ' ' ); //Inclused <space>DegreeSymble
						var location = ii.address;
						var gpsTime = ii.time; //TODO Check this timezone
						var lon = listGetAt( ii.lon, 1, ' ' ); //Inclused <space>DegreeSymble
						var lat = listGetAt( ii.lat, 1, ' ' ); //Inclused <space>DegreeSymble
						var odometer = ii.Odometer;
						//End data parse

						if ( val( intEquipmentId ) ){ //Found truck, now log it
							var thisTruckPosition = {
								intEquipmentId: val( intEquipmentId )
								,intSpeed: speed
								,intHeading: heading
								,latitude: lat
								,longitude: lon
								,tspLocation: gpsTime
								,tspBoltReceived: now()
								,bitIgnition: 0
								,bitIgnitionNoData: 0
								,strLocation: location
							};

							if ( isNumeric( odometer ) && val( intEquipmentId ) && isDate(gpsTime) ){
								setTruckOdometer(
									intEquipmentId: val( intEquipmentId )
									,tspTimeStamp: gpsTime
									,decOdometer: odometer
								);
							}
							arrayAppend(aryBreadcrumbs, thisTruckPosition);
						}
					}
					writeOutput("#arraylen(aryBreadcrumbs)# breadcrumbs processed <br>");
					setTransaction( 'BREADCRUMBS', dateAdd( 's', 1, lastGPSTime ) ); //ARG! Telogis GREATERTHAN in the template is actually EQUAL TO OR GREATER THAN, have to bump up the transaction time by 1 second.
					setPosition( 11, aryBreadcrumbs ); //11 is Telogis
				} else {
					writeOutput("No Breadcrumbs <br>");
				}
			} else {
				//Nothing to Process
				writeOutput('<br>Nothing to Process in breadcrumbs');
			}
		</cfscript>
		<!---
			[Template]
			TemplateVersion = 1.0
			TableID = Point-2.0
			TemplateName = Breadcrumbs7
			OrderBy = Input.Time
			Format = JSON

			#Can have multiple intents separated by commas.
			Intent = Retrieve
			Output = CompleteSuccessful
			OutputHeader = true

			[Output]
			UnitId = Input.UnitId
			DriverId = Input.DriverId
			Time = Input.Time
			Lat = Input.Lat
			Lon = Input.Lon
			Address = Input.Address
			Heading = Input.Heading
			SerialNumber = Input.SerialNumber
			Tag = Input.Tag

			[User]
			TimeStart(Timestamp) = ""

			[Filter]
			Time = GreaterThan(TimeStart)
		--->
	</cffunction>

	<cffunction name="setTruckOdometer" returntype="void" >
		<cfargument name="intEquipmentId" type="numeric" required="true" />
		<cfargument name="decOdometer" type="numeric" required="true" />
		<cfargument name="tspTimeStamp" type="string" required="true" />

		<cfscript>
			var qryDeleteOdometer = '';
			var qrySetOdometer = '';
			var gpsTime = "#dateFormat(arguments.tspTimeStamp, 'YYYY-MM-DD')# #TimeFormat(arguments.tspTimeStamp,'HH:mm:ss')#";
			var odom = NumberFormat(arguments.decOdometer,'999.9');
		</cfscript>

		<cfquery name="qrySetOdometer" datasource="#variables.dsn#">
			DELETE FROM
				telogis.tblrecentodometer
			WHERE
				fkEquipmentId = <cfqueryparam cfsqltype="cf_sql_integer" value="#val( arguments.intEquipmentId )#" />
		</cfquery>
		<cfquery name="qrySetOdometer" datasource="#variables.dsn#" >
			INSERT INTO
				telogis.TBLRECENTODOMETER
				(
					decodometer
					,fkequipmentid
					,tsprecorded
				)
			VALUES
				(
					<cfqueryparam cfsqltype="cf_sql_decimal" value="#val( odom )#" scale="1" />
					,<cfqueryparam cfsqltype="cf_sql_integer" value="#val( arguments.intEquipmentId )#" />
					,<cfqueryparam cfsqltype="cf_sql_timestamp" value="#gpsTime#" />
				)
		</cfquery>
	</cffunction>

	<cffunction name="getTruckOdometer" returntype="Numeric" >
		<cfargument name="intEquipmentId" type="numeric" required="true" />

		<cfscript>
			var qryGetTruckOdometer = '';
		</cfscript>

		<cfquery name="qryGetTruckOdometer" datasource="#variables.dsn#" >
			SELECT
				decOdometer
			FROM
				telogis.tblrecentodometer
			WHERE
				fkEquipmentId = <cfqueryparam cfsqltype="cf_sql_integer" value="#val( arguments.intEquipmentId )#" />
		</cfquery>

		<cfreturn val( qryGetTruckOdometer.decOdometer ) />
	</cffunction>

	<cffunction name="getTemplateId" returntype="Struct" access="public" >
		<cfargument name="strTemplateName" type="string" required="true" >

		<cfscript>
			var qryGetTemplateId = '';
			var rtn = {
				templateId: 0
				,telogisTemplateName: ''
			};
		</cfscript>

		<cfquery datasource="#variables.dsn#" name="qryGetTemplateId" cachedWithin="#createTimeSpan( 0, 0, 0, 30 )#" >
			SELECT
				t.strTELOGISTEMPLATENAME AS telogistemplatename
				,t.intTEMPLATEID AS templateid
			FROM
				telogis.tbltemplates t
			WHERE
				t.strBOLTTEMPLATENAME = <cfqueryparam value="#trim( ucase(arguments.strTemplateName ) )#" cfsqltype="cf_sql_varchar" >
		</cfquery>

		<cfscript>
			rtn.templateId = val( qryGetTemplateId.templateid );
			rtn.telogisTemplateName = qryGetTemplateId.telogistemplatename;

			return rtn;
		</cfscript>
	</cffunction>

	<cffunction name="callTemplate" returntype="Any" access="public" >
		<cfargument name="template" type="numeric" required="true" default="0" />
		<cfargument name="params" type="struct" required="false" default="#{}#" />
		<cfargument name="body" type="string" required="false" default="" />
		<cfargument name="methodType" type="string" required="true" default="GET" />

		<cfscript>
			var defaultRtn = {};
			var isAuth = false;
			var httpService = new http();
			httpService.setMethod( arguments.methodType );
			httpService.setUrl( '#variables.strTelogisURL#/execute' );
			//Adds URL Query Params
			arguments.params.auth = variables.telogisToken;
			if ( !structKeyExists(arguments.params, 'template') && len( arguments.template ) ){
				arguments.params.template = arguments.template;
			}
			for ( var k IN arguments.params ){
				httpService.addParam(
					name: k
					,value: arguments.params[k]
					,type: 'URL'
				);
			}

			if ( len( trim( arguments.body ) ) ){
				httpService.addParam(
					value: trim( arguments.body )
					,type: 'BODY'
				);
			}

			var httpResult = httpService.send().getPrefix();

			if ( httpResult.ResponseHeader.Status_Code != 200 ){
				logTelogis("Error on HTTP Request (#arguments.template#)");
				logTelogis("#SerializeJSON(httpResult)#");
				if ( httpResult.ResponseHeader.Status_Code == 401 ){
					writeOutput('Getting new Telogis API token.');
					authentication();
					abort;
				}
				return defaultRtn;
			} else {
				logTelogis("Called Template #arguments.template#, no errors");
			}

			var returnContent = httpResult.Filecontent;
			//var jsonResults = httpResult.Filecontent;
			if ( isJSON( returnContent ) && arguments.methodType == 'GET' ){
				var objResults = deserializeJSON(returnContent);
				isAuth = checkAuthStatus( objResults );
				if ( isAuth ){
					//Authorized! GO!
					for ( var i IN objResults ){ //This loop is to return only the TableEntry data from the Telogis return, this should clean up code outside of this function looking for the key of the structure in the return data, but... It will probably come back to bite me.
						return objResults[i];
					}

				} else {
					writeOutput("NOPE! Cant Do Anything, Check logs");
					authentication();
					return defaultRtn;
				}
			} else if ( isJSON( returnContent ) && arguments.methodType == 'POST' ){
				var objResults = deserializeJSON(returnContent);
				if ( isStruct(objResults) ){
					return 200; //No return need from this data. Just deleteing records
				}
				if ( isArray( objResults ) && arrayLen(objResults) == 1 ){
					return objResults[1];
				} else {
					return objResults;
				}
			} else {
				return defaultRtn;
			}
		</cfscript>
	</cffunction>

	<cffunction name="checkAuthStatus" returntype="boolean" access="private" >
		<cfargument name="jsonToCheck" type="struct" required="true" />

		<cfscript>
			rtn = false;
			if ( structKeyExists(arguments.jsonToCheck, 'errorInfo') ){
				//Telogis Returned Error
				logTelogis( arguments.jsonToCheck.errorInfo[1].errorText );
			} else {
				return true;
			}
			return rtn;
		</cfscript>
	</cffunction>

	<cffunction name="authentication" returntype="struct" >
		<cfscript>
			logTelogis('Getting new auth code');
			var telogisLoginURL = '#variables.strTelogisURL#/rest/login';
			var rtn = {
				token: ''
				,customerName: ''
				,username: ''
				,customerId: ''
				,userId: ''
				,apiHost: ''
				,result: ''
				,error: false
			};

			if ( len( variables.strTelogisPassword ) && len( variables.strTelogisUsername ) ){
				//TODO: Try Authendication
				rtn.result = 'Logon Attemtped';
				logonPars = {
					'username': variables.strTelogisUsername
					,'password': variables.strTelogisPassword
				};

				var httpService = new http();
				httpService.setMethod('POST');
				httpService.setUrl(telogisLoginURL);
				httpService.addParam(type:'header',name:'Content-Type',value:'application/json');
				httpService.addParam(type:'body', value: SerializeJSON( logonPars ) );
				var httpResult = httpService.send().getPrefix();
				writeDump(httpResult);

				if ( isJson( httpResult.Filecontent ) ){
					var httpResultObj = deserializeJson( httpResult.Filecontent );
					//Got a  Telogis error
					if ( structKeyExists(httpResultObj,'errorInfo') ){
						rtn.error = true;
						rtn.result = httpResultObj.errorText;
						return rtn;
					} else if ( structKeyExists(httpResultObj,'token') && len( trim( httpResultObj.token ) ) ) {
						setTelogisApplicationVariable( trim( httpResultObj.token ) );
						variables.telogisToken = getTelogisToken(); //Reset the component variable.
					}
				} else {
					rtn.error = true;
					rtn.result = 'Invalid Packet from Telogis';
					return rtn;
				}
			} else {
				rtn.result = 'Missing Telogis Credentials';
				rtn.error = true;
			}
			return rtn;
		</cfscript>
	</cffunction>

	<cffunction name="setTelogisApplicationVariable" returntype="String" >
		<cfargument name="telogisToken" type="string" required="true" default="" />

		<cfscript>
			var qryUpdateTelogisToken = '';
		</cfscript>

		<cfquery name="qryUpdateTelogisToken" datasource="#variables.dsn#" >
			UPDATE
				live.tblapplicationvariables
			SET
				strValue = <cfqueryparam value="#arguments.telogisToken#" cfsqltype="cf_sql_varchar" />
			WHERE
				upper(strname) = 'STRTELOGISTOKEN'
		</cfquery>
	</cffunction>

	<cffunction name="getTelogisToken" returntype="String" access="public" >
		<cfscript>
			var qryGetTelogisToken = '';
		</cfscript>

		<cfquery name="qryGetTelogisToken" datasource="#variables.dsn#" >
			SELECT
				strValue
			FROM
				live.tblapplicationvariables
			WHERE
				upper( strname ) = 'STRTELOGISTOKEN'
		</cfquery>

		<cfif qryGetTelogisToken.recordcount EQ 0 >
			<cfquery name="qryInsertApplicationVariable" datasource="#variables.dsn#" >
				INSERT INTO
					live.tblapplicationvariables
					( strName, strValue )
				VALUES
					('STRTELOGISTOKEN', '0')
			</cfquery>
		</cfif>

		<cfscript>
			return qryGetTelogisToken.strValue;
		</cfscript>
	</cffunction>

	<cffunction name="logTelogis" returntype="void" >
		<cfargument name="strLogMessage" type="string" />

		<cfscript>
			if ( !directoryExists( '#application.strclientpath#\telogis\' ) ){
				directoryCreate( '#application.strclientpath#\telogis\' );
			}
			var _log = fileOpen( '#application.strclientpath#\telogis\telogislog.txt', 'append' );
			fileWriteLine( _log, dateformat( now(), 'yyyymmdd') & ' ' & timeformat( now(), 'HHmmss ' ) & arguments.strLogMessage );
		</cfscript>
	</cffunction>

	<cffunction name="getTransaction" returntype="Any" >
		<cfargument name="strService" required="true" />

		<cfscript>
			var qryGetTransaction = '';
		</cfscript>

		<cfquery name="qryGetTransaction" datasource="#variables.dsn#" >
			SELECT
				tspLastPull AS lastPullDateTime
			FROM
				telogis.tblTransaction
			WHERE
				upper(strService) = <cfqueryparam cfsqltype="cf_sql_varchar" value="#trim(ucase( arguments.strService ) )#" />
		</cfquery>

		<cfscript>
			if ( qryGetTransaction.recordcount == 0 ){
				setTransactionEntry( trim( arguments.strService ) );
				return 0;
			} else {
				return qryGetTransaction.lastPullDateTime;
			}
		</cfscript>
	</cffunction>

	<cffunction name="setTransactionEntry" returntype="Any" >
		<cfargument name="strService" required="true" />

		<cfscript>
			qryInsertTransactionEntry = '';
		</cfscript>

		<cfquery name="qryInsertTransactionEntry" datasource="#variables.dsn#" >
			INSERT INTO
				telogis.tblTransaction
				( strService, tspLastPull )
			VALUES
				(
					<cfqueryparam cfsqltype="cf_sql_varchar" value="#trim(ucase( arguments.strService ) )#" />
					, <cfqueryparam cfsqltype="cf_sql_timestamp" value="#application.bolt.timezone.toUTC( dateTime = now(), timeZone = 'Central' )#" >
				)
		</cfquery>
	</cffunction>

	<cffunction name="setTransaction" returntype="void" >
		<cfargument name="strService" required="true" />
		<cfargument name="tspTransactionTime" required="true" />

		<cfscript>
			var qryUpdateTransaction = '';
		</cfscript>

		<cfquery name="qryUpdateTransaction" datasource="#variables.dsn#" >
			UPDATE
				telogis.tblTransaction
			SET
				tspLastPull = <cfqueryparam cfsqltype="cf_sql_timestamp" value="#arguments.tspTransactionTime#" />
			WHERE
				upper(strService) = <cfqueryparam cfsqltype="cf_sql_varchar" value="#trim(ucase( arguments.strService ) )#" />
		</cfquery>
	</cffunction>

	<cffunction name="getTruck" access="public" returntype="numeric" >
		<cfargument name="truckName" />
		<cfscript>
			var equipmentId = 0;

			// serach only power units
			var _etQry = application.bolt.equipment.getEquipmentTypes( bitPowerUnit = true ).result;
			var _et = [ valueList(_etQry.intEquipmentTypeId) ];
			var _e = application.bolt.equipment.getEquipment(
					aryEquipmentTypeId = _et
					//,intOBCVendorId = variables.intOBCVendorId
					,strEquipmentName = arguments.truckName
					,bitExactNameMatch: true
					,aryTerminalId = []
					,cacheMinutes: 1
				).result;

			equipmentId = isNumeric( _e.intEquipmentId ) ? _e.intEquipmentId : 0;

			// search by BOLT truck name instead
			if ( !equipmentId ) {

				_e = application.bolt.equipment.getEquipment(
						aryEquipmentTypeId = _et
						,strEquipmentName = arguments.truckName
						,aryTerminalId = []
					).result;

				equipmentId = isNumeric( _e.intEquipmentId ) ? _e.intEquipmentId : 0;
			}

			return equipmentId;
		</cfscript>
	</cffunction>

	<!--- Telogis Template Actions --->
	<!--- Retreieve ---->

	<cffunction name="getTerritories" returntype="Any" >
		<cfargument name="templateId" required="true" default="0" />

		<cfscript>
			var parms = {
				'template': arguments.templateId
			};
			var territories = callTemplate(
				params: parms
			);
			if ( structKeyExists(territories, 'GetTerritories') ){
				//Has Resutls
				return	territories.TableEntry;
			} else {
				return [];
			}
		</cfscript>
	</cffunction>

	<cffunction name="getDrivers" returntype="Any" >
		<cfargument name="templateId" required="true" default="0" />

		<cfscript>
			var parms = {
				'template': arguments.templateId
			};
			var Drivers = callTemplate(
				params: parms
			);
			if ( structKeyExists(Drivers, 'AllDrivers') ){
				//Has Resutls
				return	Drivers.TableEntry;
			} else {
				return [];
			}
		</cfscript>
	</cffunction>

	<cffunction name="GetMarkerByBOLTCustomerId" returntype="Any" >
		<cfargument name="templateId" required="true" default="0" type="numeric" />
		<cfargument name="strBoltCustomerId" required="true" default="" type="string" />

		<cfscript>
			var parms = {
				'template': arguments.templateId
				,'BOLTCustomerId': arguments.strBoltCustomerId
			};

			var Markers = callTemplate(
				params: parms
			);
			if ( structKeyExists(Markers, 'GetMarkerByBOLTCustomerId') ){
				//Has Resutls
				return	Markers.TableEntry;
			} else {
				return [];
			}
		</cfscript>
	</cffunction>

	<!--- Create --->
	<cffunction name="createUpdateMarker" returntype="Any" >
		<cfargument name="templateId" type="numeric" required="true" />
		<cfargument name="companyData" type="struct" required="true" />

		<cfscript>
			var parms = {
				'template': arguments.templateId
			};

			var csv = createCsvFromStruct( arguments.companyData );

			var Markers = callTemplate(
				params: parms,
				body: csv,
				methodType: 'POST'
			);
			//writeDump(['markers in cfc',Markers]);
			if ( structKeyExists(Markers, '_detail') && Markers._detail.succeeded == 'YES' ){
				//Has Resutls
				return Markers.id;
			} else {
				return '';
			}
		</cfscript>
	</cffunction>

	<cffunction name="createUpdateRoute" returntype="Any" >
		<cfargument name="routeData" type="struct" required="true" />

		<cfscript>
			var routeTemplate = getTemplateId( 'ROUTECREATE' ).templateId;
			var parms = {
				'template': routeTemplate
			};

			var csv = createCsvFromStruct( arguments.routeData );

			var Route = callTemplate(
				params: parms,
				body: csv,
				methodType: 'POST'
			);
			if ( structKeyExists(Route, '_detail') && Route._detail.succeeded == 'YES' ){
				//Has Resutls
				return Route['Id'];
			} else {
				return [];
			}
		</cfscript>
	</cffunction>

	<cffunction name="createUpdateJob" returntype="Any" >
		<cfargument name="templateId" type="numeric" required="true" />
		<cfargument name="jobData" type="array" required="true" />

		<cfscript>
			var parms = {
				'template': arguments.templateId
			};

			var csv = createCsvFromArray( arguments.jobData );

			var job = callTemplate(
				params: parms,
				body: csv,
				methodType: 'POST'
			);

			for ( var i IN job ){
				storeJobId( boltStopId: i['id(BoltStopId)'], telogisJobId: i.Id );
			}

			//writeOutput("Jobs Created <br>");
			return job;
		</cfscript>
	</cffunction>

	<cffunction name="deleteJobs" returntype="Void" >
		<cfargument name="stopData" type="array" required="true" />

		<cfscript>
			var parms = {
				'template': getTemplateId('JOBDELETE').templateId
			};

			var csv = createCsvFromArray( arguments.stopData );

			var job_delete = callTemplate(
				params: parms,
				body: csv,
				methodType: 'POST'
			);
			logTelogis("Deleting #arraylen(arguments.stopData)# jobs");
		</cfscript>
	</cffunction>

	<!--- CSV Stuff --->
	<cffunction name="createCsvFromStruct" returntype="String" >
		<cfargument name="structData" type="struct" required="true" default="{}" >

		<cfscript>
			var csv = '';
			var lineDelim = chr( 13 ) & chr( 10 );
			var csvColumns = StructKeyList(arguments.structData);
			var DataLine = '';
			var string = '';
			var newString = '';
			csv = csv & csvColumns & lineDelim;

			for( var i=1; i <= listLen(csvColumns); i++ ){
				string = arguments.structData[ listGetAt(csvColumns,i) ];
				newString = replace( string, ',',' ','all' );
				DataLine = listAppend( DataLine, newString );
			}
			csv = csv & DataLine;
			return csv;
		</cfscript>
	</cffunction>

	<cffunction name="createCsvFromArray" returntype="String" >
		<cfargument name="arrayData" type="array" required="true" default="#[]#" >

		<cfscript>
			var csv = '';
			var lineDelim = chr( 13 ) & chr( 10 );
			var csvColumns = StructKeyList(arguments.arrayData[1]);
			var DataLine = '';
			var string = '';
			var newString = '';
			csv = csv & csvColumns & lineDelim;

			for( x IN arrayData ){
				DataLine = '';
				for( var i=1; i <= listLen(csvColumns); i++ ){
					string = x[ listGetAt(csvColumns,i) ];
					newString = replace( string, ',',' ','all' );
					DataLine = listAppend( DataLine, newString );
				}
				csv = csv & DataLine & lineDelim;
			}
			return csv;
		</cfscript>
	</cffunction>

	<!--- Template Function - REST --->
	<cffunction name="getTemplates" returntype="Any" description="Gets current tempaltes on Telogis system" >
		<cfscript>
			var httpService = new http();
			httpService.setMethod('GET');
			httpService.setUrl( '#variables.strTelogisURL#/templates' );
			//Adds URL Query Params
			httpService.addParam(
					name: 'auth'
					,value: variables.telogisToken
					,type: 'URL'
				);

			var httpResult = httpService.send().getPrefix();
			if ( httpResult.StatusCode == '401 Unauthorized' ){
				authentication();
				writeOutput('Reautorized Telogis, please try again');
				abort;
			} else {
				return deserializeJSON( httpResult.Filecontent );
			}
		</cfscript>
	</cffunction>

	<cffunction name="getForms" returntype="Any" description="Gets current Forms on Telogis system" >
		<cfscript>
			var httpService2 = new http();
			httpService2.setMethod('GET');
			httpService2.setUrl( '#variables.strTelogisURL#/rest/form_templates' );
			//Adds URL Query Params
			httpService2.addParam(
					name: 'auth'
					,value: variables.telogisToken
					,type: 'URL'
				);

			var httpResult = httpService2.send().getPrefix();
			if ( httpResult.StatusCode == '401 Unauthorized' ){
				authentication();
				writeOutput('Reautorized Telogis, please try again');
				abort;
			} else {
				return deserializeJSON( httpResult.Filecontent );
			}
		</cfscript>
	</cffunction>

	<cffunction name="getJobTypesParams" returntype="Any" description="Gets current Forms on Telogis system" >
		<cfscript>
			var httpService2 = new http();
			httpService2.setMethod('GET');
			httpService2.setUrl( '#variables.strTelogisURL#/rest/job_Types' );
			//Adds URL Query Params
			httpService2.addParam(
					name: 'auth'
					,value: variables.telogisToken
					,type: 'URL'
				);

			var httpResult = httpService2.send().getPrefix();
			if ( httpResult.StatusCode == '401 Unauthorized' ){
				authentication();
				writeOutput('Reautorized Telogis, please try again');
				abort;
			} else {
				return deserializeJSON( httpResult.Filecontent );
			}
		</cfscript>
	</cffunction>

	<cffunction name="getTemplateDefinition" returntype="Any" description="Gets the template definition" >
		<cfargument name="templateId" type="numeric" required="true" />
		<cfscript>
			var httpService = new http();
			httpService.setMethod('GET');
			httpService.setUrl( '#variables.strTelogisURL#/templates/#arguments.templateId#' );
			//Adds URL Query Params
			httpService.addParam(
					name: 'auth'
					,value: variables.telogisToken
					,type: 'URL'
				);

			var httpResult = httpService.send().getPrefix();
			return httpResult.Filecontent;
		</cfscript>
	</cffunction>

	<cffunction name="deleteTemplate" returntype="Any" description="Deletes a template" >
		<cfargument name="templateId" type="numeric" required="true" />
		<cfscript>
			var httpService = new http();
			httpService.setMethod('DELETE');
			httpService.setUrl( '#variables.strTelogisURL#/templates/#arguments.templateId#' );
			//Adds URL Query Params
			httpService.addParam(
					name: 'auth'
					,value: variables.telogisToken
					,type: 'URL'
				);

			var httpResult = httpService.send().getPrefix();
			return httpResult.Filecontent;
		</cfscript>
	</cffunction>

	<!--- Work Flow --->
	<cffunction name="sendWorkflow" access="public" returntype="Any" >
		<cfargument name="intLoadId" type="numeric" required="true" />
		<cfargument name="intDriverId" type="numeric" required="false" />
		<cfargument name="telogisIds" type="struct" required="true" />

		<cfscript>
			var unitTemplate = getTemplateId('UNIT');
			var unitData = callTemplate(
				template: unitTemplate.templateId
				,params: {
					unitId: telogisIds.unitId
				}
			);
			if ( arrayLen(unitData.TableEntry) == 0 ){
				logTelogis( "No Unit ID Matched" );
				return '';
			}
			var strTruckName = unitData.TableEntry[1].Tag;
			logTelogis( "Start Sending Workflow to truck: #strTruckName#, load #intLoadId#" );
			var intTruckId = getTruck( strTruckName );

			var territoryId = callTemplate(
				template: getTemplateId('TERRITORY').templateId
				,params: {
					'TerritoryName': 'BOLT'
				}
			).TableEntry[1].Id;

			var workflow = '';
			var _theJobs = [];
			var load = '';
			var i = 1;
			var _arystopId = [];
			var loadOpts = {
				intLoadId = arguments.intLoadId
			};
			var sendSuccess = false;
			var jobTypeIds = getJobTypes();

			var terminalTz = '';
			var stopTz = '';
			var tzDiff = 0;

			if ( structKeyExists( arguments, 'intDriverId' ) ) {
				loadOpts.intDriverId = arguments.intDriverId;
			}

			// get the trip segment data
			load = application.bolt.dispatch.getLoadSegment( argumentCollection = loadOpts ).result;

			if ( isDebugMode() ) {
				//writeDump( load );
			}

			// if the trip segment is not already assigned to this vehicle fix it...
			// force assignment will override the truck assignment on the segment
			if ( ( !val( load.intTruckId ) || variables.forceAssignment )
				&& structKeyExists( arguments,'intDriverId' )
				) {

				makeSegmentAssignments(
					loadSegment = load
					,intTruckId = intTruckId
					,intDriverId = arguments.intDriverId
				);

			}

			terminalTz = application.bolt.timezone.getCompaniesAddressTZ( load.intTerminalId_Hauling );

			for ( var i=1; i lte load.recordCount; i++ ) {

				// prevent stops that have already occurred from being
				// sent to the OBC (for example the truck broke down and the
				// driver cancelled the workflow on the original obc and the requested
				// again in the replacement vehicle )
				if ( !arrayFind( _arystopId, load.intStopId[i] ) && !len( load.tspArrived[i] ) ) { //Only send unarrived stops

					// get stop offset and compare with terminal offset to get the
					// offset factor to apply to the stop time
					stopTz = application.bolt.timezone.getCompaniesAddressTZ( load.intCompaniesAddressID_Stop[ i ] );

					// use te stops timezone when available
					if ( val( stopTz.intOffset ) ) {
						tzDiff = ( abs( val( stopTz.intOffset ) ) - abs( val( terminalTz.intOffset ) ) ) * -1;
					} else {
						// try harder to get the stop to terminal offset by using the stop's zip code
						stopTz = application.bolt.timeZone.getZipCodeTimeZone( [ left( load.strPostal_Stop[ i ], 5 ) ] ).result;
						stopTz = application.bolt.timeZone.getTimeZone( aryTimeZone = [ left( stopTz.strTimeZone, 3 ) ] ).result;

						// and if that fails just use the terminal's offset and don't change the stop time sent
						if ( val( tzDiff ) ) {
							tzDiff = ( abs( val( stopTz.intTZOffset ) ) - abs( val( terminalTz.intOffset ) ) ) * -1;
						} else {
							tzDiff = 0;
						}
					}

					// for filtering out dups on Spot Trailer
					arrayAppend( _arystopId, load.intStopId[i] );

					var adjStartTime = dateAdd( 'h', tzDiff, load.tspScheduledArrive[i] );
					var formattedStartTime = '#DateFormat(adjStartTime,'YYYY-MM-DD')#T#TimeFormat(adjStartTime,'HH:MM:00')#';

					arrayAppend( _theJobs,
						{
							stopId = load.intStopID[i]
							,stopType = load.strStopTypeName[i]
							,stopLocation = load.strCompanyName_Stop[i]
							,stopScheduled = formattedStartTime
							,exceptions = []
							//,tasks = getStopTasks( load.strStopTypeName[i] )
							,location = {
								latitude = load.realLatitude_Stop[i]
								,longitude = load.realLongitude_Stop[i]
								,radius = load.intArrivedRadius_Stop[i]
								,city = load.strcity_stop[i]
								,state = load.strState_Stop[i]
								,street = load.strStreet1_stop[i]
								,zip = load.strPostal_Stop[i]
								,companiesAddressId = load.intCompaniesAddressId_stop[i]
								,name = load.strCompanyName_stop[i]
								,companyCode = load.strCompanyCode_stop[i]
								,territoryId = territoryId
								,stopType = load.strStopTypeName[i]
								,addressId = load.intAddressId[i]
								//,notificationType = variables.arrivalDriverInteraction
							}
							,hasArrived = isDate( load.tspArrived[i] )
							,hasDeparted = isDate( load.tspDeparted[i] )
							,intStopId = load.intStopId[i]
						}
					);

				}

			}

			/*
				Array of Structures of all the [Output]'s in the template
				[Output]
				Name = Input.Name
				DriverId = Input.DriverId
				UnitId = Input.UnitId
				TerritoryId = Input.TerritoryId
				StartTime(yyyy-MM-ddTHH:mm:ss, UTC) = Input.StartTime
				EndTime(yyyy-MM-ddTHH:mm:ss, UTC) = Input.EndTime
			*/

			var structRoute = {
				'Name': ''
				,'DriverId': '' //Telogis Driver Id
				,'UnitId': '' //Telogis Unit Id
				,'TerritoryId': ''//Telogis Territory Id
				,'StartTime': '' //Start of Load
				,'EndTime': '' //End of Load
			};

			var startLocation = '';
			var endLoacation = '';

			for ( var y IN _theJobs ){
				if ( !len(structRoute.StartTime) ){
					structRoute.StartTime = y.stopScheduled; //First Stop Time
					startLocation = y.location.city;
				}
				structRoute.EndTime = y.stopScheduled; //Last STop Time
				endLoacation = y.location.city;
			};

			structRoute.Name = 'Bolt Pro: #val(arguments.intLoadId)#';
			structRoute.UnitId = telogisIds.unitId;
			structRoute.DriverId = telogisIds.driverId;
			structRoute.TerritoryId = territoryId;

			var routeID = createUpdateRoute( structRoute );
			var markerData = {
				'id': '',
				'companyName': '',
				'tag': '', //Same as Company Name
				'CustomerId': '',
				'StreetNumber': '',
				'StreetName': '',
				'City': '',
				'Region': '',
				'PostalCode': '',
				'Country': 'USA',
				'TerritoryId': territoryId,
				'Lat': '',
				'Lon': '',
				'MarkerType': 0, //Center point of circle
				'Radius': 5 //Feet
			};

			/*
			[Output]
			ExpectedArrivalTime(yyyy-MM-ddTHH:mm:ss, UTC) = Input.ExpectedArrivalTime
			ExpectedDepartureTime(yyyy-MM-ddTHH:mm:ss, UTC) = Input.ExpectedDepartureTime
			ExpectedTravelDistance(mi) = Input.ExpectedTravelDistance
			Priority = Input.Priority
			RouteId = Input.RouteId
			DriverId = Input.DriverId
			UnitId = Input.UnitId
			TerritoryId = Input.TerritoryId
			MarkerId = Input.MarkerId
			JobTypeId = Input.JobTypeId
			*/

			var structJob = {
				'ExpectedArrivalTime': ''
				,'ExpectedDepartureTime': ''
				,'ExpectedTravelDistance': ''
				,'Priority': ''
				,'RouteId': ''
				,'DriverId': ''
				,'UnitId': ''
				,'TerritoryId': ''
				,'MarkerId': ''
				,'JobTypeId': ''
			};

			var stopCounter = 0;
			var aryJobs = [];
			var aryStopIds = [];

			for ( var p IN _theJobs ){
				stopCounter++;
				if ( !val( p.location.latitude ) && !val( p.location.longitude ) ){ //No lat or Long
					var geocode2 = {};
					geocode2 = geoCodeAddress(
						address = {
							'street': p.location.street
							,'city': p.location.city
							,'state': p.location.state
							,'zip': p.location.zip
							,'id': p.location.addressId
						}
					);
				} else {
					geocode2.lat = p.location.latitude;
					geocode2.lon = p.location.longitude;
				}

				if ( !val( geocode2.lat ) && !val( geocode2.lon ) ){ //Still no lat long... Default marker to center of US
					geocode2.lat = 39.8283;
					geocode2.lon = -98.5794;
				}

				markerData = {
					'id': 'bolt_#p.location.companiesAddressId#',
					'companyName': p.location.name,
					'tag': p.location.name, //Same as Company Name
					'CustomerId': p.location.companyCode,
					'StreetNumber': val( trim( listGetAt( p.location.street, 1, ' ' ) ) ), //Gets House number
					'StreetName': trim( ListRest( p.location.street, ' ' ) ), //Gets Street Name
					'City': p.location.city,
					'Region': p.location.state,
					'PostalCode': (len(p.location.zip)?p.location.zip:'00000'),
					'Country': 'USA',
					'TerritoryId': territoryId,
					'Lat': geocode2.lat,
					'Lon': geocode2.lon,
					'MarkerType': 0, //Center point of circle
					'Radius': 5 //Feet
				};

				markerReturnData = createUpdateMarker( templateId: getTemplateId('MARKER').templateId, companyData: markerData );
				markerId = markerReturnData;

				var thisStopType = ''; //Default to Stop if not found...
				if ( structKeyExists( jobTypeIds, p.stopType ) ){
					thisStopType = jobTypeIds[ p.stopType ];
				} else {
					thisStopType = jobTypeIds[ 'Stop' ]; //Default to STOP when Job type is not in Telogis
				}

				if( isNumeric(markerId) ){
						structJob = {
						'ExpectedArrivalTime': p.stopScheduled
						,'ExpectedDepartureTime': p.stopScheduled
						,'ExpectedTravelDistance': 0 //TODO: Mile Since Previous Stop
						,'Priority': 'Normal'
						,'RouteId': routeID
						,'DriverId': telogisIds.driverId
						,'UnitId': telogisIds.unitId
						,'TerritoryId': territoryId
						,'MarkerId': markerId
						,'JobTypeId': thisStopType
						,'BoltStopId': p.intStopId
					};
					arrayAppend(aryJobs,structJob);
					arrayAppend(aryStopIds,{'boltStopId':p.intStopId});
				}

			}
			//Delete Old Jobs
			deleteJobs( stopData: aryStopIds );

			jobCreated = createUpdateJob( templateId: getTemplateId('JOB').templateId, jobData: aryJobs );
		</cfscript>

		<cfif val( load.intLoadId ) && arrayLen( _theJobs ) >
			<cfscript>
				application.bolt.dispatch.setLoadStatus(
						intLoadId: load.intLoadId
						,intStatus: 2
						,intAuditUserId: arguments.intDriverId
					);
			</cfscript>
		<cfelse>

			<cfreturn false />

		</cfif>
	</cffunction>

	<cffunction name="storeJobId" returntype="void" >
		<cfargument name="boltStopId" type="numeric" required="true" />
		<cfargument name="telogisJobId" type="string" required="true" />
		<cfscript>
			var qryDeleteStopRecords = '';
			var qryInsertStopRecords = '';
		</cfscript>

		<cfquery datasource="#variables.dsn#" name="qryDeleteStopRecords" >
			DELETE FROM
				telogis.tblStops
			WHERE
				fkStopId = <cfqueryparam value="#arguments.boltStopId#" cfsqltype="cf_sql_bigint" >
		</cfquery>
		<cfquery datasource="#variables.dsn#" name="qryInsertStopRecords" >
			INSERT INTO
				telogis.tblStops
			(
				fkStopId
				,strTELOGISJOBID
			)
			VALUES
			(
				<cfqueryparam value="#arguments.boltStopId#" cfsqltype="cf_sql_bigint" >
				,<cfqueryparam value="#arguments.telogisJobId#" cfsqltype="cf_sql_char" >
			)
		</cfquery>
	</cffunction>

	<cffunction name="removeStopId" returntype="void" >
		<cfargument name="telogisJobId" type="string" required="true" />

		<cfscript>
			var qryremoveStopId = '';
		</cfscript>

		<cfquery name="qryremoveStopId" datasource="#variables.dsn#" >
			DELETE FROM
				telogis.tblStops
			WHERE
				strTELOGISJOBID = <cfqueryparam value="#arguments.telogisJobId#" cfsqltype="cf_sql_char" />
		</cfquery>
	</cffunction>

	<cffunction name="makeSegmentAssignments" access="public" returntype="void" >
		<cfargument name="loadSegment" />
		<cfargument name="intTruckId" type="numeric" />
		<cfargument name="intTrailerId" type="numeric" />
		<cfargument name="intTrailerSequence" type="numeric" default="0" />
		<cfargument name="intDriverId" type="numeric" default="0" />
		<cfargument name="recursionCall" type="boolean" required="false" default="false" />
		<!---
			I can't wait for this code to be deprecated...
			Did my best to encapsulate it here to prevent damaged / bugs from leaked vars, etc
		--->

		<cfscript>
			var stopAssign = createObject( 'component', 'boltAppRoot.cfc.stopAssign' );
			var intAssignLoadId = arguments.loadSegment.intLoadId;
			var intLoadId = intAssignloadId;
			var intSequence = arguments.loadSegment.intStopSequence;
			var intTrucksPerStopId = arguments.loadSegment.intTrucksPerStopId;
			var getrow1tps = '';
			var getrow1TruckCount = '';
			var getStopSequence = '';

			if (
			    	!arguments.recursionCall
			    	&& structKeyExists( arguments.loadSegment, 'intStopSequence' )
			    	&& arguments.loadSegment.intStopSequence eq 100
			    	&& structKeyExists( arguments.loadSegment, 'strStopType' )
			    	&& arguments.loadSegment.strStopType eq 'Spot Trailer'
			    ) {
				// assign first segment of the Spot Trailer

				// don't mess up the original data
				var _args = duplicate( arguments );

				// don't loop forever
				_args.recursionCall = true;

				// manufacture what the recusion call needs to work
				_args.loadSegment = {
										intLoadId = arguments.loadSegment.intLoadId
										,intStopSequence = arguments.loadSegment.intStopSequence
										,intTrucksPerStopId = getFirstTPSforStop( arguments.loadSegment.intStopId )
										,strStopType = arguments.loadSegment.strStopType
										,intTruckSequence = 0
										,intDPTSequence = arguments.loadSegment.intDPTSequence
									};


				// do it!
				makeSegmentAssignments(	argumentCollection = _args );
			}

			include '/boltAppRoot/queries/qryAssignAssets.cfm';

			if ( val( intAssignloadId ) && structKeyExists( arguments, 'intTruckId' ) && val( arguments.intTruckId ) ) {

				try {
					stopAssign.truck(
									intLoadId = intAssignLoadId
									,intTruckId = arguments.intTruckId
									,intTPSId = intTrucksPerStopId
									,intTPSSequence = arguments.loadSegment.intTruckSequence
									,stopData = getStopSequence
									,row1rc = getrow1tps.recordCount
									,row1tc = val( getrow1TruckCount.truckCount )
									,intAuditUserId = arguments.intDriverId
								);
				} catch ( any e ) {

				}

			}

			if ( val( intAssignloadId ) && structKeyExists( arguments, 'intDriverId' ) && val( arguments.intDriverId ) && structKeyExists( arguments.loadSegment, 'intDPTSequence' ) && val( arguments.loadSegment.intDPTSequence ) ) {

				try {
					stopAssign.driver(
									intLoadId = intAssignLoadId
									,intDriverId = arguments.intDriverId
									,intTPSId = intTrucksPerStopId
									,intTPSSequence = arguments.loadSegment.intTruckSequence
									,intDriverSequence = arguments.loadSegment.intDPTSequence
									,stopData = getStopSequence
									,row1rc = getrow1tps.recordCount
									,row1tc = val( getrow1TruckCount.truckCount )
									,intAuditUserId = arguments.intDriverId
								);
				} catch ( any e ) {

				}
			}

			if ( val( intAssignloadId ) && structKeyExists( arguments,'intTrailerId' ) && val( arguments.intTrailerId ) ) {

				try {
					stopAssign.trailer(
									intLoadId = intAssignLoadId
									,intTrailerId = arguments.intTrailerId
									,intTPSId = intTrucksPerStopId
									,intTPSSequence = arguments.loadSegment.intTruckSequence
									,intTrailerSequence = arguments.intTrailerSequence
									,stopData = getStopSequence
									,row1rc = getrow1tps.recordCount
									,row1tc = val( getrow1TruckCount.truckCount )
									,intAuditUserId = arguments.intDriverId
								);
				} catch ( any e ) {

				}

			}
		</cfscript>
	</cffunction>

	<cffunction name="getTelogisStops" returntype="string" >
		<cfscript>
			var getTelogisStops = '';
		</cfscript>
		<cfquery datasource="#variables.dsn#" name="qryGetTelogisStops" >
			SELECT
				strTELOGISJOBID AS telogisJobId
			FROM
				telogis.tblStops
		</cfquery>

		<cfreturn valuelist( qryGetTelogisStops.telogisJobId ) />
	</cffunction>

	<cffunction name="getJobTypes" returntype="Any" >
		<cfscript>
			var jobTypeIds = {};
			var jobTypeTemplate = getTemplateId('JOBTYPES');
			var jobTypeData = callTemplate(
					template: jobTypeTemplate.templateId
					,params: {
					}
				).TableEntry;
			for( jobType IN jobTypeData ){
				jobTypeIds[jobType.Name] = jobType.id;
			}

			return jobTypeIds;
		</cfscript>
	</cffunction>

	<!--- Misc Functions --->
	<cffunction name="formatTelogisDateTime" returntype="String" >
		<cfargument name="dateTime" type="string" required="true" >

		<cfscript>
			if( isDate( dateTime ) ){
				return '#dateFormat(arguments.dateTime, 'yyyy-mm-dd')#T#timeFormat(arguments.dateTime, 'HH:MM:ss')#';
			} else {
				return '';
			}
		</cfscript>
	</cffunction>

	<cffunction name="findBoltStopId" returntype="Numeric" >
		<cfargument name="telogisJobId" required="true" >

		<cfscript>
			var qryFindBoltStopId = '';
		</cfscript>

		<cfquery name="qryFindBoltStopId" datasource="#variables.dsn#" >
			SELECT
				s.fkStopId AS boltStopid
			FROM
				telogis.tblstops s
			WHERE
				s.strTELOGISJOBID = <cfqueryparam value="#arguments.telogisJobId#" cfsqltype="cf_sql_char" />
		</cfquery>

		<cfreturn val( qryFindBoltStopId.boltStopid ) />
	</cffunction>

	<cffunction name="getLoadIdByStopId" returntype="Numeric" >
		<cfargument name="intStopId" type="numeric" required="true" />

		<cfscript>
			var qryGetLoadIdByStopId = '';
		</cfscript>

		<cfquery datasource="#variables.dsn#" name="qryGetLoadIdByStopId" >
			SELECT
				pols.fkloadsid
			FROM
				live.tblpurchaseordersloadsstops pols
			WHERE
				pols.fkstopsid = <cfqueryparam value="#arguments.intStopId#" cfsqltype="cf_sql_integer" />
			FETCH FIRST 1 ROWS ONLY
		</cfquery>

		<cfreturn val( qryGetLoadIdByStopId.fkLoadsId ) />
	</cffunction>

	<cffunction name="stopCleanup" returntype="void" access="public" >
		<cfscript>
			var cleanupTelogisStops = '';
		</cfscript>

		<cfquery datasource="#variables.dsn#" name="cleanupTelogisStops" >
			DELETE FROM
				telogis.tblstops s1
			WHERE
				s1.fkStopId IN (
				SELECT
					s.fkStopId
				FROM
					telogis.tblstops s
				JOIN
					live.tblpurchaseordersloadsstops pols
					ON
					pols.fkstopsid = s.fkStopId
				JOIN
					live.tblloads l
					ON
					l.intid = pols.fkloadsid
				WHERE
					l.fkloadstatus <> 2
				OR
					l.bitActive = '0'
			)
		</cfquery>
	</cffunction>

	<cffunction name="geoCodeAddress" returntype="Any" access="public" >
		<cfargument name="address" type="struct" required="true" >

		<cfhttp url="http://gmaps.boltsystem.com/getlatlong.cfm" method="post" >
			<cfhttpparam type="url" value="#arguments.address.street#, #arguments.address.city#, #arguments.address.state#" name="address" >
		</cfhttp>

		<cfscript>
			var geoCodeAddressRtn = {
				lat = 0
				, lon = 0
			};
			var ulatlong = '';
			if ( cfhttp.StatusCode == '200 OK' ){
				var lat = listgetat( cfhttp.FileContent, 1, chr( 183 ) );
				var long = listgetat( cfhttp.FileContent, 2, chr( 183 ) );
			} else {
				return geoCodeAddressRtn;
			}

		</cfscript>
		<cfquery datasource="#application.dsn#" name="ulatlong" >
			UPDATE
				live.tbladdress
			SET
				latitude = <cfqueryparam cfsqltype="cf_sql_double" value="#lat#" />
				,longitude = <cfqueryparam cfsqltype="cf_sql_double" value="#long#" />
			WHERE
				id = <cfqueryparam cfsqltype="cf_sql_integer" value="#val( address.id )#" />
		</cfquery>

		<cfscript>
			return {'lat':lat,'lon':long};
		</cfscript>
	</cffunction>
</cfcomponent>