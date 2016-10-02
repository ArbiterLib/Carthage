import Arbiter

class ArbiterValueBox<T: Comparable where T: Hashable>: ArbiterValue, CustomStringConvertible {
  init(_ value: T) {
    self.unbox = value
  }

  let unbox: T

  var hashValue: Int {
    return unbox.hashValue
  }

  var description: String {
    return "\(unbox)"
  }
}

func ==<T: Equatable>(lhs: ArbiterValueBox<T>, rhs: ArbiterValueBox<T>) -> Bool {
  return lhs.unbox == rhs.unbox
}

func <<T: Comparable>(lhs: ArbiterValueBox<T>, rhs: ArbiterValueBox<T>) -> Bool {
  return lhs.unbox < rhs.unbox
}

extension PinnedVersion: Hashable, Comparable {
  public var hashValue: Int {
    return commitish.hashValue
  }
}

public func <(lhs: PinnedVersion, rhs: PinnedVersion) -> Bool {
	return lhs.commitish < rhs.commitish
}

extension ProjectIdentifier {
  typealias ArbiterType = Arbiter.ProjectIdentifier<ArbiterValueBox<ProjectIdentifier>>

  func toArbiter() -> ArbiterType {
    return Arbiter.ProjectIdentifier(value: ArbiterValueBox(self))
  }

  static func fromArbiter(x: ArbiterType) -> ProjectIdentifier {
    return x.value.unbox
  }
}

extension SemanticVersion {
  typealias ArbiterType = Arbiter.SemanticVersion

  func toArbiter() -> ArbiterType {
    return Arbiter.SemanticVersion(major: major, minor: minor, patch: patch)
  }

  static func fromArbiter(x: ArbiterType) -> SemanticVersion {
    precondition(x.prereleaseVersion == nil)
    precondition(x.buildMetadata == nil)

    return SemanticVersion(major: x.major, minor: x.minor, patch: x.patch)
  }
}

extension PinnedVersion {
  typealias ArbiterType = Arbiter.SelectedVersion<ArbiterValueBox<PinnedVersion>>

  func toArbiter() -> ArbiterType {
    let semVer = try? SemanticVersion.fromPinnedVersion(self).dematerialize()
    return Arbiter.SelectedVersion(semanticVersion: semVer?.toArbiter(), metadata: ArbiterValueBox(self))
  }

  static func fromArbiter(x: ArbiterType) -> PinnedVersion {
    return x.metadata.unbox
  }
}

extension VersionSpecifier {
  typealias ArbiterType = Arbiter.Requirement

  func toArbiter() -> ArbiterType {
    switch self {
    case .Any:
      return Arbiter.Requirement(Specifier.Any)

    case let .AtLeast(version):
      return Arbiter.Requirement(Specifier.AtLeast(version.toArbiter()))

    case let .CompatibleWith(version):
      return Arbiter.Requirement(Specifier.CompatibleWith(version.toArbiter(), ArbiterRequirementStrictnessAllowVersionZeroPatches))

    case let .Exactly(version):
      return Arbiter.Requirement(Specifier.Exactly(version.toArbiter()))

    case .GitReference:
      // TODO: Use an unversioned or custom requirement with higher priority
      return Arbiter.Requirement(Specifier.Any)
    }
  }
}

func dependencyToArbiter(dependency: Dependency<VersionSpecifier>) -> Arbiter.Dependency<ArbiterValueBox<ProjectIdentifier>> {
  return Arbiter.Dependency(project: dependency.project.toArbiter(), requirement: dependency.version.toArbiter())
}

func dependencyFromArbiter(dependency: Arbiter.ResolvedDependency<ArbiterValueBox<ProjectIdentifier>, ArbiterValueBox<PinnedVersion>>) -> Dependency<PinnedVersion> {
  let project = ProjectIdentifier.fromArbiter(dependency.project)
  let version = PinnedVersion.fromArbiter(dependency.version)
  return Dependency(project: project, version: version)
}

extension Cartfile {
  typealias ArbiterType = Arbiter.DependencyList<ArbiterValueBox<ProjectIdentifier>>

  func toArbiter() -> ArbiterType {
    return Arbiter.DependencyList(dependencies.map(dependencyToArbiter))
  }
}

extension ResolvedCartfile {
  typealias ArbiterType = Arbiter.ResolvedDependencyGraph<ArbiterValueBox<ProjectIdentifier>, ArbiterValueBox<PinnedVersion>>

  static func fromArbiter(x: ArbiterType) -> ResolvedCartfile {
    let installer = Arbiter.ResolvedDependencyInstaller(graph: x)

    return ResolvedCartfile(dependencies: installer.phases.flatMap { phase in
      return phase.map(dependencyFromArbiter)
    })
  }
}
