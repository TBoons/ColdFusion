<br>
<cfscript>
	if ( structKeyExists( application,'strSambaSafetyAccountId' ) && structKeyExists( application,'strSambaSafetyUserName' ) && structKeyExists( application,'strSambaSafetyPassword' ) ){
			productionURL = 'https://eapi.sambasafety.com:8443/EnterpriseApi/v1/mvrs/receive/';
			//Demo Credentials
			// "accountId" : 4698,
			// "userName" : "rtdemo",
			// "password" : "TEST"
			demoURL = 'https://eapi-demo.sambasafety.com/EnterpriseApi/v1/mvrs/receive/';
			credentials = {
				"credentials" : {
				"accountId" : application.strSambaSafetyAccountId,
				"userName" : application.strSambaSafetyUserName,
				"password" : application.strSambaSafetyPassword
				},
				"mvrFormat" : "REKLAMI DL XML RT 2.03"
			};

			// ********* DEMO *****************
			// credentials = {
			// 	"credentials" : {
			// 	"accountId" : 4698, //application.strSambaSafetyAccountId,
			// 	"userName" : 'rtdemo', //application.strSambaSafetyUserName,
			// 	"password" : 'TEST' //application.strSambaSafetyPassword
			// 	},
			// 	"mvrFormat" : "REKLAMI DL XML RT 2.03"
			// };
	} else {
		abort;
	};
</cfscript>

<cfhttp url="#productionURL#" method="post" result="sambraSafetyReturn" resolveurl="yes" timeout="240" >
	<cfhttpparam type="body" value="#serializeJSON( credentials )#" >
</cfhttp>

<cfscript>

	if ( !isJSON(sambraSafetyReturn.FileContent) ){
		writeOutput("#sambraSafetyReturn.FileContent#");
		filewrite( '#application.strclientpath#\logs\sambaXML\#DateFormat(now(),'yyyymmdd')##Timeformat(now(),'HHmmss')#.json', sambraSafetyReturn.FileContent );
		abort;
	}

	filewrite( '#application.strclientpath#\logs\sambaXML\#DateFormat(now(),'yyyymmdd')##Timeformat(now(),'HHmmss')#.json', sambraSafetyReturn.FileContent );

	sambaMRVData = DeserializeJSON( sambraSafetyReturn.FileContent );

	results = [];
	if ( arrayLen(sambaMRVData) ){
		for (  t=1; t <= arrayLen(sambaMRVData); t++ ){
			logFilename = CreateUUID();
			filewrite( '#application.strclientpath#\logs\sambaXML\#logFilename#.xml', sambaMRVData[t].data );

			_data = xmlParse(sambaMRVData[t].data);
			for ( i=1; i <= arrayLen( _data.Record ); i++ ){
				updateDriverExp = false;
				driverResult = '';
				if ( !structKeyExists( _data.Record[i].DlRecord, 'Driver' ) ){
					//No Driver Found
					if ( structKeyExists(_data.Record[i].DlRecord, 'CurrentLicense') && structKeyExists( _data.Record[i].DlRecord.CurrentLicense,'Number' ) ){
						//Has a license number
						arrayAppend(results,{
							'firstName': '',
							'lastName': '',
							'BOLTdriverId': '',
							'licenseNumber': _data.Record[i].DlRecord.CurrentLicense.Number.XmlText,
							'result': 'Driver Not Found',
							'updateDriverExp': '',
							'cdlExpDate': '',
							'medicalExp': '',
							'mvrDate': '',
							'logFilename': logFilename
						});
					}
				} else {
					//Driver Found
					if ( structKeyExists(_data.Record[i].DlRecord.Criteria, 'LicenseNumber') ){
						// Has Lic Number
						licenseNumber = _data.Record[i].DlRecord.Criteria.LicenseNumber.XmlText;
						intDriverId = getDriverIdByLicenseNumber( licenseNumber );
					} else {
						//No Lic Number
						licenseNumber = '';
						intDriverId = 0;
					}

					if ( structKeyExists(_data.Record[i].DlRecord.Driver, 'FirstName') && structKeyExists(_data.Record[i].DlRecord.Driver, 'FirstName') ){
						//Has Name
						strDriverFirstName = _data.Record[i].DlRecord.Driver.FirstName.XmlText;
						strDriverLastName = _data.Record[i].DlRecord.Driver.LastName.XmlText;
					} else {
						//No Name
						strDriverFirstName = 'NA';
						strDriverLastName = 'NA';
					}

					thisDriverMVRDate = '';
					if ( structKeyExists( _data.Record[i].DlRecord, 'Criteria' ) ){
						//Criteria found
						if ( structKeyExists(_data.Record[i].DlRecord.Criteria, 'OrderDate') ){
							//Order Date Found, use this as MVR Date
							thisDriverMVRDate = _data.Record[i].DlRecord.Criteria.OrderDate.Year.XmlText & '-' & _data.Record[i].DlRecord.Criteria.OrderDate.Month.XmlText & '-'  & _data.Record[i].DlRecord.Criteria.OrderDate.Day.XmlText;
							driverResult = listAppend(driverResult,'MVR Found ');
							updateDriverExp = true;
						}
					} else {
						driverResult = listAppend(driverResult,'No MVR Date for this Driver ');
					}

					switch( intDriverId ){
						case -1:
							driverResult = listAppend(driverResult,'Multi drivers found with same License Number ');
						break;
						case 0.:
							driverResult = listAppend(driverResult,'No Driver Found in BOLT with License Number ');
						break;
						default:
							driverResult = listAppend(driverResult,'License Number Updated ');
							updateDriverExp = true;
						break;
					}

					if ( updateDriverExp && isDate( thisDriverMVRDate ) ){
						application.bolt.user.setDriverDetail(
							intUserId: intDriverId
							,datLastMVR: thisDriverMVRDate
							,intAuditUserId: 0
						);
					} else {
						driverResult = listAppend(driverResult,'No MVR Update ');
					}

					cdlExpDate = '';
					if ( !structKeyExists( _data.Record[i].DlRecord.CurrentLicense, 'Commercial' ) ){
						driverResult = listAppend(driverResult,'No Commercial Record ');
					} else {
						thisCDLRecord = _data.Record[i].DlRecord.CurrentLicense.Commercial;

						if ( structKeyExists( thisCDLRecord, 'ExpirationDate' ) ){
							//Has Expiration Date
							cdlExpDate = thisCDLRecord.ExpirationDate.Year.XmlText & '-' & thisCDLRecord.ExpirationDate.Month.XmlText & '-'  & thisCDLRecord.ExpirationDate.Day.XmlText;
						} else {
							driverResult = listAppend(driverResult,'No Commercial Date ');
						}

					}

					if ( updateDriverExp && isDate( cdlExpDate ) ){
						application.bolt.user.setDriverDetail(
							intUserId: intDriverId
							,datLicenseExpiration: cdlExpDate
							,intAuditUserId: 0
						);
					} else {
						driverResult = listAppend(driverResult,'No Commercial Update ');
					}

					medicalExpDate = '';
					if ( !structKeyExists( _data.Record[i].DlRecord, 'MedicalCertificateList' ) ){
						driverResult = listAppend(driverResult,'No Medical ');
					} else {
						thisMedicalRecord = _data.Record[i].DlRecord.MedicalCertificateList;
						if ( structKeyExists(thisMedicalRecord, 'MedicalCertificateItem') ){
							//Has Medical Item
							thisMedicalRecordItem = thisMedicalRecord.MedicalCertificateItem;
							if ( structKeyExists(thisMedicalRecordItem, 'ExpirationDate') ){
								//Has Expiration
								medicalExpDate = thisMedicalRecordItem.ExpirationDate.Year.XmlText & '-' & thisMedicalRecordItem.ExpirationDate.Month.XmlText & '-'  & thisMedicalRecordItem.ExpirationDate.Day.XmlText;
							} else {
								driverResult = listAppend(driverResult,'No Medical Expiration Date ');
							}

						} else {
							driverResult = listAppend(driverResult,'No Medical ');
						}
					}

					if ( updateDriverExp && isDate( medicalExpDate ) ){
						application.bolt.user.setDriverDetail(
							intUserId: intDriverId
							,datMedicalExpiration: medicalExpDate
							,intAuditUserId: 0
						);
					} else {
						driverResult = listAppend(driverResult,'No Medical Update ');
					}

					arrayAppend(results,{
							'firstName': strDriverFirstName,
							'lastName': strDriverLastName,
							'BOLTdriverId': intDriverId,
							'licenseNumber': licenseNumber,
							'result': driverResult,
							'updateDriverExp': updateDriverExp,
							'cdlExpDate': cdlExpDate,
							'medicalExp': medicalExpDate,
							'mvrDate': thisDriverMVRDate,
							'logFilename': logFilename
						});
				}
			}
		}
	} else {
	}
</cfscript>
<cfoutput>
	<table width="80%" border="1">
		<tr>
			<th>
				Driver
			</th>
			<th>
				License Number
			</th>
			<th>
				MVR Date
			</th>
			<th>
				CDL Expiratation Date
			</th>
			<th>
				Medical Exp
			</th>
			<th>
				Result
			</th>
		</tr>
		<cfloop array="#results#" index="driver">
			<cffile action="append" file="#application.strclientpath#/logs/sambaDriverLicenseImport.txt" output="#now()# - #driver.firstName# #driver.lastName# (#logFilename#) - #driver.licenseNumber# - #driver.cdlExpDate# - #driver.medicalExp# - #driver.result#" addnewline="true" />
			<tr>
				<td>
					#driver.firstName# #driver.lastName#
				</td>
				<td>
					#driver.licenseNumber#
				</td>
				<td>
					#driver.mvrDate#
				</td>
				<td>
					#driver.cdlExpDate#
				</td>
				<td>
					#driver.medicalExp#
				</td>
				<td>
					#driver.result#
				</td>
			</tr>
		</cfloop>
	</table>
</cfoutput>

<cffunction name="getDriverIdByLicenseNumber" returntype="Numeric" >
	<cfargument name="strLicenseNumber" type="string" required="true" >

	<cfquery name="qryGetDriverId" datasource="#application.dsn#" >
		SELECT
			u.intid
			,u.strfirstname
			,u.strlastname
			,dd.strlicense
		FROM
			live.tblusers u
		JOIN
			live.tbldriverdetails dd
			ON
			dd.fkdriverid = u.intid
		WHERE
			dd.strlicense = <cfqueryparam cfsqltype="cf_sql_varchar" value="#arguments.strLicenseNumber#" />
		AND
			u.bitDriver = '1'
		AND
			u.bitActive = '1'
	</cfquery>

	<cfif qryGetDriverId.recordcount GT 1 >
		<cfreturn -1 />
	<cfelseif qryGetDriverId.recordcount EQ 1 >
		<cfreturn val( qryGetDriverId.intid ) />
	<cfelse>
		<cfreturn 0 />
	</cfif>
</cffunction>