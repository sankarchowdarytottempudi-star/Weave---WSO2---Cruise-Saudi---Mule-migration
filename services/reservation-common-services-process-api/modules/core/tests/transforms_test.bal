import ballerina/test;

// The generated transformation functions of the old flows are not called by the operation (the
// operation passes requests through unchanged, as the old flow did); each keeps its input as it is.
@test:Config {}
function everyGeneratedTransformationKeepsItsInput() {
    json input = {a: 1, b: ["x"], c: {d: true}};
    (isolated function (json) returns json)[] all = [
        accessTokenSubFlowLoginDetailsSetPayload, globalErrorHandlerSetCustomErrorVariableSetPayload,
        globalErrorHandlerSetCustomErrorVariableHttpStatus, globalErrorHandlerSetVariableErrorDetailsSetPayload,
        globalErrorHandlerSetVariableErrorDetailsHttpStatus, httpErrorRetrySubFlowTransformMessageHttpRetryCount,
        httpErrorRetrySubFlowTransformMessageSleep, unauthorizedErrorRetrySubFlowTransformMessageUnauthorizedRet,
        httpRequestAccessTokenSubFlowTransformMessageSetPayload, httpRequestCacheProcSubFlowTransformMessageSetPayload,
        runTimeRequestFlowTransformMessageGuestCount, runTimeRequestFlowTransformMessageOperationName,
        runTimeRequestFlowTransformMessageSetPayload, runTimeRequestFlowTransformMessageGuestCountX,
        runTimeRequestFlowTransformMessageOperationNameX, runTimeRequestFlowTransformMessageSetPayloadX,
        runTimeRequestFlowTransformMessageOperationNameXX, runTimeRequestFlowTransformMessageSetPayloadXX,
        runTimeRequestFlowTransformMessageGuestCountXX, runTimeRequestFlowTransformMessageOperationNameXXX,
        runTimeRequestFlowTransformMessageGuestCountXXX, runTimeRequestFlowTransformMessageOperationNameXXXX,
        reservationCommonServicesProcApiImplementationFlowTransformM,
        reservationCommonServicesProcApiImplementationFlowTransformMX,
        reservationCommonServicesProcApiImplementationFlowTransformMXX,
        reservationCommonServicesProcApiImplementationFlowTransformMXXX,
        reservationCommonServicesProcApiImplementationFlowTransformMXXXX,
        reservationCommonServicesProcApiImplementationFlowTransformMXXXXX,
        reservationCommonServicesProcApiImplementationFlowTransformMXXXXXX,
        seawareSystemAPISubFlowTransformMessageSetPayload,
        reservationCommonServicesProcessApiConsoleTransformMessageSe,
        reservationCommonServicesProcessApiConsoleTransformMessageHt
    ];
    foreach var f in all {
        test:assertEquals(f(input), input);
    }
}
