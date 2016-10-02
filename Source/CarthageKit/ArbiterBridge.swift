import Arbiter

// This file contains internal utilities for bridging between CarthageKit's
// public API and the use of Arbiter as an implementation detail.
//
// Even though Arbiter may offer richer features in some cases, we avoid them
// when necessary in favor of backwards compatibility for Carthage.

/**
 * Used to give identity to CarthageKit value types, so they can be associated
 * with Arbiter data types.
 */
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

/**
 * Extends PinnedVersion with the requirements needed for ArbiterValueBox.
 */
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

    case let .GitReference(commitish):
      return Arbiter.Requirement(Specifier.Any)
      /*
      TODO: This needs a rework in Arbiter, because as written here, the requirement is never satisfied
      (consider commitishes specified here, but which get expanded into full commit hashes during lookup)

      let pinnedVersion = PinnedVersion(commitish)
      let unversionedSpecifier = Specifier.Unversioned(ArbiterValueBox<PinnedVersion>(pinnedVersion).toUserValue())
      return Arbiter.Requirement(Specifier.Prioritized(unversionedSpecifier, 10))
      */
    }
  }
}

func dependencyToArbiter(dependency: Dependency<VersionSpecifier>) -> Arbiter.Dependency<ArbiterValueBox<ProjectIdentifier>> {
  return Arbiter.Dependency(project: dependency.project.toArbiter(), requirement: dependency.version.toArbiter())
}

func dependencyToArbiter(dependency: Dependency<PinnedVersion>) -> Arbiter.ResolvedDependency<ArbiterValueBox<ProjectIdentifier>, ArbiterValueBox<PinnedVersion>> {
  return Arbiter.ResolvedDependency(project: dependency.project.toArbiter(), version: dependency.version.toArbiter())
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
