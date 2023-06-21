import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum ReasyncMacro: PeerMacro {
    private struct Diagnostic {
        enum Kind: DiagnosticMessage {
            case notAnAsyncFunction(decl: DeclSyntax)
            case noAsyncParameter(function: FunctionDeclSyntax)
            case awaitExprWithoutAsyncParameter(awaitKeyword: TokenSyntax)

            var message: String {
                switch self {
                case .notAnAsyncFunction:
                    "Reasync macro can only be applied to an async function"
                case .noAsyncParameter:
                    "Reasync macro can only be applied to an async function that has at least one async parameter"
                case .awaitExprWithoutAsyncParameter:
                    "@Reasync function cannot call an async function that is not in the parameter list"
                }
            }

            var diagnosticID: MessageID {
                let id = switch self {
                case .notAnAsyncFunction:
                    "notAnAsyncFunction"
                case .noAsyncParameter:
                    "noAsyncParameter"
                case .awaitExprWithoutAsyncParameter:
                    "awaitExprWithoutAsyncParameter"
                }

                return .init(domain: "MacroTest", id: id)
            }

            var severity: DiagnosticSeverity {
                .error
            }
        }

        let kind: Kind

        var diagnostic: SwiftDiagnostics.Diagnostic {
            let node: Syntax = switch kind {
            case let .notAnAsyncFunction(decl):
                .init(decl)
            case let .noAsyncParameter(function):
                .init(function)
            case let .awaitExprWithoutAsyncParameter(awaitKeyword):
                .init(awaitKeyword)
            }

            return .init(node: node, message: kind)
        }
    }

    private class SearchParameterVisitor: SyntaxAnyVisitor {
        private let asyncParameterNames: [String]

        private(set) var foundAsyncParameter = false

        init(asyncParameterNames: [String]) {
            self.asyncParameterNames = asyncParameterNames

            super.init(viewMode: .sourceAccurate)
        }

        override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
            guard !self.foundAsyncParameter else {
                return .skipChildren
            }

            if let identifierExpr = node.as(IdentifierExprSyntax.self),
                asyncParameterNames.contains(identifierExpr.identifier.text) {
                self.foundAsyncParameter = true
                return .skipChildren
            }

            return .visitChildren
        }
    }

    private class RemoveAwaitVisitor: SyntaxRewriter {
        private(set) var diagnostics: [Diagnostic] = []

        private let asyncParameterNames: [String]

        init(asyncParameterNames: [String]) {
            self.asyncParameterNames = asyncParameterNames
        }

        override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
            let visitor = SearchParameterVisitor(asyncParameterNames: asyncParameterNames)
            visitor.walk(node)

            guard visitor.foundAsyncParameter else {
                diagnostics.append(.init(kind:
                    .awaitExprWithoutAsyncParameter(
                        awaitKeyword: node.awaitKeyword
                    )
                ))

                return .init(node)
            }

            return node.expression.with(
                \.leadingTrivia,
                node.awaitKeyword.leadingTrivia
            )
        }
    }


    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self),
            let body = function.body,
            let effectSpecifiers = function.signature.effectSpecifiers,
            effectSpecifiers.asyncSpecifier != nil else {
            context.diagnose(
                Diagnostic(
                    kind: .notAnAsyncFunction(decl: .init(declaration))
                ).diagnostic
            )
            return []
        }

        var asyncParameterNames: [String] = []
        let parameterList = FunctionParameterListSyntax(
            function.signature.input.parameterList.map { parameter in
                if let type = parameter.type.as(FunctionTypeSyntax.self),
                    let effectSpecifiers = type.effectSpecifiers,
                    effectSpecifiers.asyncSpecifier != nil {
                    asyncParameterNames.append((parameter.secondName ?? parameter.firstName).text)

                    return parameter.with(
                        \.type,
                        .init(type.with(
                            \.effectSpecifiers,
                            effectSpecifiers.with(
                                \.asyncSpecifier,
                                nil
                            )
                        ))
                    )
                } else {
                    return parameter
                }
            }
        )

        guard !asyncParameterNames.isEmpty else {
            context.diagnose(
                Diagnostic(
                    kind: .noAsyncParameter(function: function)
                ).diagnostic
            )

            return []
        }

        let attributes = AttributeListSyntax(
            function.attributes?.filter {
                guard case let .attribute(attribute) = $0,
                    let attributeType = attribute.attributeName.as(SimpleTypeIdentifierSyntax.self),
                    let nodeType = node.attributeName.as(SimpleTypeIdentifierSyntax.self)
                else {
                    return true
                }

                return attributeType.name.text != nodeType.name.text
            } ?? []
        )

        let removeAwaitVisitor = RemoveAwaitVisitor(asyncParameterNames: asyncParameterNames)
        let newBody = removeAwaitVisitor.visit(body)

        guard removeAwaitVisitor.diagnostics.isEmpty else {
            for diagnostic in removeAwaitVisitor.diagnostics {
                context.diagnose(diagnostic.diagnostic)
            }

            return []
        }

        return [
            .init(
                function.with(
                    \.attributes,
                    attributes
                ).with(
                    \.signature,
                    function.signature.with(
                        \.input.parameterList,
                        parameterList
                    ).with(
                        \.effectSpecifiers,
                        effectSpecifiers.with(
                            \.asyncSpecifier,
                            nil
                        )
                    )
                ).with(
                    \.body,
                    newBody
                ).with(
                    \.leadingTrivia,
                    .newlines(2)
                )
            )
        ]
    }
}
