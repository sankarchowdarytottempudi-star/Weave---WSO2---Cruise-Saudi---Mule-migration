# Notes for whoever finishes this service

Written in the Factory ("Finish this migration"). One section per open item.

## db-system-api-flow

- 2026-11-15T10:41:21Z: Update the DB with details wether the call was success or failed
- 2026-11-15T10:44:36Z: <?xml version="1.0" encoding="UTF-8"?>
<mule xmlns:db="http://www.mulesoft.org/schema/mule/db"
      xmlns:ee="http://www.mulesoft.org/schema/mule/ee/core"
      xmlns:http="http://www.mulesoft.org/schema/mule/http"
      xmlns="http://www.mulesoft.org/schema/mule/core"
      xmlns:doc="http://www.mulesoft.org/schema/mule/documentation"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.mulesoft.org/schema/mule/core http://www.mulesoft.org/schema/mule/core/current/mule.xsd
http://www.mulesoft.org/schema/mule/http http://www.mulesoft.org/schema/mule/http/current/mule-http.xsd
http://www.mulesoft.org/schema/mule/ee/core http://www.mulesoft.org/schema/mule/ee/core/current/mule-ee.xsd
http://www.mulesoft.org/schema/mule/db http://www.mulesoft.org/schema/mule/db/current/mule-db.xsd">

    <flow name="db-system-api-flow">

        <http:listener path="${httpListener.path}" config-ref="common_SYS_API_Listener">
            <http:response statusCode="#[vars.httpStatus default 200]"/>
            <http:error-response statusCode="#[vars.httpStatus default 500]">
                <http:body><![CDATA[#[output application/json --- payload]]]></http:body>
            </http:error-response>
        </http:listener>

        <ee:transform doc:name="Extract Request Variables" doc:id="8604287b-b2fc-461f-a6d1-dd81489a09d8">
            <ee:variables>
                <ee:set-variable variableName="correlationId"><![CDATA[%dw 2.0
output application/java
---
attributes.headers.correlationId default uuid()]]></ee:set-variable>
				<ee:set-variable variableName="DBData" ><![CDATA[%dw 2.0
output application/json
var data = payload
---
{
	connectionKey: data.connectionKey default "",
    operation: lower(data.operation default ""),
    query: data.query default "",
    params: data.params default {}
}]]></ee:set-variable>
				<ee:set-variable variableName="connectionCheck" ><![CDATA[%dw 2.0
output application/java
var connection=  payload.connectionKey
---
if (connection == "PG_ShipTracking") "postgres_db_shipTracking_implSub_Flow"
 else if(connection == "PG_Guest") "postgres_db_guest_implSub_Flow"
 else null]]></ee:set-variable>
            </ee:variables>
        </ee:transform>

        <set-variable value="#[correlationId]" doc:name="correlationId" doc:id="353d5fdc-893a-4063-a5f5-3b79fc18ae6d" variableName="correlationId" />
       	<logger level="INFO" message='#["DB sys api flow started correlationId: #[vars.correlationid] operation: #[vars.DBData.operation] connectionKey: #[vars.DBData.connectionKey]"]'/>

        <choice doc:name="Validate Request">
    <when expression='#[vars.connectionCheck != null and !isEmpty(vars.connectionCheck)]'>
        <flow-ref name="#[vars.connectionCheck]" doc:name="Dynamic DB Flow"/>
    </when>
    <otherwise>
        <logger level="WARN" message='#["Invalid request - connectionCheck: #[vars.connectionCheck] operation: #[vars.DBData.operation] correlationId: #[vars.correlationId]"]'/>
        <!-- [STUDIO:"Set Bad Request Response"]<ee:transform doc:name="Set Bad Request Response">
            <ee:message>
                <ee:set-payload><![CDATA[%dw 2.0
output application/json
&#45;&#45;-
{
    correlationId: vars.correlationId default "UNKNOWN",
    messageType: "BAD_REQUEST",
    message: "Invalid connectionKey provided",
    responseCode: 400
}&#93;&#93;></ee:set-payload>
            </ee:message>
            <ee:variables>
                <ee:set-variable variableName="httpStatus"><![CDATA[400&#93;&#93;></ee:set-variable>
            </ee:variables>
        </ee:transform> [STUDIO] -->
				<raise-error 
    doc:name="Raise error"
    type="APP:UNAUTHORIZED"
    description='#["Invalid operation or not implemented: " ++ (vars.DBData.operation default "unknown")]'/>
    </otherwise>
</choice>

        <ee:transform doc:name="Transform Message" doc:id="58753fa2-bcd7-40d9-b55d-2ac3aad009c0">
            <ee:message>
                <ee:set-payload><![CDATA[%dw 2.0
ou
