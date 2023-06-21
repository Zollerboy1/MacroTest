@attached(accessor, names: named(didSet))
public macro Test() = #externalMacro(
    module: "MacroTestImpl",
    type: "TestMacro"
)

public enum Visibility { case `private`, `internal`, `public` }

@attached(member, names: named(init))
public macro initializer(_ visibility: Visibility = .internal) = #externalMacro(
    module: "MacroTestImpl",
    type: "InitializerMacro"
)

@attached(peer, names: overloaded)
public macro Reasync() = #externalMacro(
    module: "MacroTestImpl",
    type: "ReasyncMacro"
)

@Reasync
func f(body: () async throws -> Void) async rethrows {
    try await body()
}

@Reasync
func g(body: () async -> Void) async {
    await f(body: body)
}
