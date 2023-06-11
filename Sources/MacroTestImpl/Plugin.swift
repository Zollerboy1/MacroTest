import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TestMacro.self,
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
