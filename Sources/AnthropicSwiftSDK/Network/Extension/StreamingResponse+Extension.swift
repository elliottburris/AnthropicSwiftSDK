//
//  StreamingResponse+Extension.swift
//  AnthropicSwiftSDK
//
//  Created by 伊藤史 on 2024/08/22.
//

import FunctionCalling

extension StreamingResponse {
    /// True if `stop_reason` of this StreamingResponse is `tool_use`
    var isToolUse: Bool {
        switch self {
        case let deltaResponse as StreamingMessageDeltaResponse:
            return deltaResponse.isToolUse
        default:
            return false
        }
    }
}

extension StreamingMessageDeltaResponse {
    /// True if `stop_reason` is `tool_use`
    var isToolUse: Bool {
        toolUseContent != nil && delta.stopReason == .toolUse
    }

    /// If this response contains the `tool_use` property, the result of the `Tool` call is obtained using the `ToolContainer` given in the argument.
    /// - Parameter toolContainer: Takes the `tool_use` in the response and returns the result.
    /// - Returns: The result of tool use
    func getToolResultContent(from toolContainer: ToolContainer) async -> Content? {
        guard let toolUseContent else {
            return nil
        }

        let result = await toolContainer.execute(methodName: toolUseContent.name, parameters: toolUseContent.input)

        return .toolResult(
            .init(
                toolUseId: toolUseContent.id,
                content: [
                    .text(result)
                ],
                isError: false
            )
        )
    }
}

extension StreamingMessageDeltaResponse {
    /// Returns a `StreamingMessageDeltaResponse` with `ToolUseContent` overwritten with the value received in the argument.
    /// - Parameter toolUseContent: `ToolUseContent` to overwrite
    /// - Returns: A `StreamingMessageDeltaResponse`overwritten
    func added(toolUseContent: ToolUseContent) -> Self {
        StreamingMessageDeltaResponse(
            type: type,
            delta: delta,
            usage: usage,
            toolUseContent: toolUseContent
        )
    }
}

extension AsyncThrowingStream where Element == StreamingResponse {
    /// Monitor AsyncThrowingStream with StreamingResponse as an element and aggregate tool_use related information.
    ///
    /// 1. retrieve the contents of the `tool_use` property from the `StreamingContentBlockStartResponse` containing `tool_use`.
    /// 2. retrieve the json fragment string from the `StreamingContentBlockDeltaResponse` containing `input_json_delta`.
    /// 3. return and stream the value of the `StreamingMessageDeltaResponse` whose `stop_reason` is `tool_use`, appended with the aggregated JSON string of `1.` and `2.`.
    ///
    /// - Returns: An AsyncThrowingStream containing aggregated Tool_use related information.
    func accumulated() throws -> AsyncThrowingStream<StreamingResponse, Error> {
        let accumulator = InputJSONDeltaAccumulator()
        let accumulativeStream = accumulator.createAccumulativeStream()

        Task {
            do {
                defer {
                    accumulator.finish()
                }

                for try await value in self {
                    try accumulator.accumulateIfNeeded(value)
                }
            } catch {
                throw error
            }
        }

        return accumulativeStream
    }
}