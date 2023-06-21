import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TestMacro.self,
        InitializerMacro.self,
        ReasyncMacro.self,
    ]
}

enum TestMacro: AccessorMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard
            let variable = declaration.as(VariableDeclSyntax.self),
            variable.bindingKeyword.tokenKind == .keyword(.var),
            variable.bindings.count == 1,
            let binding = variable.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            return []
        }

        let name = pattern.identifier.trimmed

        if case let .accessors(block) = binding.accessor,
            let didSetAccessor = block.accessors.first(where: {
                $0.accessorKind.tokenKind == .keyword(.didSet)
            }),
            let didSetAccessorBody = didSetAccessor.body {
            let didSetParameter = didSetAccessor.parameter?.name ?? "oldValue"
            return [
                """
                didSet(\(didSetParameter)) {
                    print("Did set \(name) to \\(\(name)) (was \\(\(didSetParameter))))")

                    do \(didSetAccessorBody)
                }
                """
            ]
        }

        return [
            """
            didSet(oldValue) {
                print("Did set \(name) to \\(\(name)) (was \\(oldValue)))")
            }
            """
        ]
    }
}

enum InitializerMacro: MemberMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            case let .argumentList(arguments) = node.argument,
            let visibilityModifier = arguments.first?.expression.as(MemberAccessExprSyntax.self)?.name.trimmed,
            let structDecl = declaration.as(StructDeclSyntax.self)
        else {
            return []
        }

        let memberVariables = structDecl.memberBlock.members.compactMap {
            $0.decl.as(VariableDeclSyntax.self)
        }.filter { !$0.hasModifier("static") }

        guard memberVariables.allSatisfy({ $0.bindings.count == 1 }) else {
            return []
        }

        let variables: [(name: TokenSyntax, type: TypeSyntax)] = memberVariables.compactMap { variable in
            guard
                let binding = variable.bindings.first,
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                let type = binding.typeAnnotation?.type
            else {
                return nil
            }

            return (name, type)
        }

        guard variables.count == memberVariables.count else {
            return []
        }

        let parameterList = variables.map { name, type in
            let type: TypeSyntax = if let functionType = type.as(FunctionTypeSyntax.self) {
                "@escaping \(functionType)"
            } else {
                type
            }

            return "\(name): \(type)"
        }.joined(separator: ", ")

        return [
            try .init(InitializerDeclSyntax(
                "\(visibilityModifier) init(\(raw: parameterList))"
            ) {
                for (name, _) in variables {
                    ExprSyntax("self.\(name) = \(name)")
                }
            }).with(\.leadingTrivia, .newlines(2))
        ]
    }
}

extension WithModifiersSyntax {
    func getModifier(_ modifier: TokenSyntax) -> DeclModifierSyntax? {
        self.modifiers?.first(where: { $0.name.tokenKind == modifier.tokenKind })
    }

    func hasModifier(_ modifier: TokenSyntax) -> Bool {
        self.getModifier(modifier) != nil
    }
}
