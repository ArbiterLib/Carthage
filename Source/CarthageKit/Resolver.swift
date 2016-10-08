//
//  Resolver.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-09.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Arbiter
import Foundation
import Result
import ReactiveCocoa

/// Responsible for resolving acyclic dependency graphs.
public struct Resolver {
	private let versionsForDependency: ProjectIdentifier -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (ProjectIdentifier, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let cartfileForDependency: Dependency<PinnedVersion> -> SignalProducer<Cartfile, CarthageError>

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available versions for a
	///                         dependency.
	/// cartfileForDependency - Loads the Cartfile for a specific version of a
	///                         dependency.
	/// resolvedGitReference  - Resolves an arbitrary Git reference to the
	///                         latest object.
	public init(versionsForDependency: ProjectIdentifier -> SignalProducer<PinnedVersion, CarthageError>, cartfileForDependency: Dependency<PinnedVersion> -> SignalProducer<Cartfile, CarthageError>, resolvedGitReference: (ProjectIdentifier, String) -> SignalProducer<PinnedVersion, CarthageError>) {
		self.versionsForDependency = versionsForDependency
		self.cartfileForDependency = cartfileForDependency
		self.resolvedGitReference = resolvedGitReference
	}

	/// Attempts to determine the latest valid version to use for each dependency
	/// specified in the given Cartfile, and all nested dependencies thereof.
	///
	/// Sends each recursive dependency with its resolved version, in the order
	/// that they should be built.
	public func resolveDependenciesInCartfile(cartfile: Cartfile, lastResolved: ResolvedCartfile? = nil, dependenciesToUpdate: [String]? = nil) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		var initialGraph: ResolvedDependencyGraph<ArbiterValueBox<ProjectIdentifier>, ArbiterValueBox<PinnedVersion>>? = nil
		if let lastResolved = lastResolved, let dependenciesToUpdate = dependenciesToUpdate where !dependenciesToUpdate.isEmpty {
			initialGraph = ResolvedDependencyGraph()

			for dependency in lastResolved.dependencies {
				if dependenciesToUpdate.indexOf(dependency.project.name) != nil {
					continue
				}

				do {
					// Cartfile.resolved doesn't have edge information, and we
					// don't actually need it here anyways.
					try initialGraph?.addNode(dependencyToArbiter(dependency), requirement: Arbiter.Requirement(Specifier.Any))
				} catch let ex as ArbiterError {
					return SignalProducer(error: CarthageError.ResolverError(ex))
				} catch {
					// TODO: Use a better error message #ErrorType
					return SignalProducer(error: CarthageError.UnresolvedDependencies([ dependency.project.name ]))
				}
			}
		}

		let resolver = Arbiter.Resolver<ArbiterValueBox<ProjectIdentifier>, ArbiterValueBox<PinnedVersion>>(
			initialGraph: initialGraph,
			dependenciesToResolve: cartfile.toArbiter(),
			listDependencies: { resolver, arbiterProject, arbiterVersion in
				let project = ProjectIdentifier.fromArbiter(arbiterProject)
				let pinnedVersion = PinnedVersion.fromArbiter(arbiterVersion)

				guard let result = self.cartfileForDependency(Dependency<PinnedVersion>(project: project, version: pinnedVersion))
					.startOn(QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "org.carthage.CarthageKit.Resolver.listDependencies"))
					.first() else {
					return Arbiter.DependencyList([])
				}

				let cartfile = try result.dematerialize()
				return cartfile.toArbiter()
			},
			listAvailableVersions: { resolver, arbiterProject in
				let project = ProjectIdentifier.fromArbiter(arbiterProject)

				let results = self.versionsForDependency(project)
					.startOn(QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "org.carthage.CarthageKit.Resolver.listAvailableVersions"))
					.collect()
					.first() ?? Result(value: [])

				let pinnedVersions = try results.dematerialize()
				return SelectedVersionList<ArbiterValueBox<PinnedVersion>>(pinnedVersions.map { $0.toArbiter() })
			},
			selectedVersionForMetadata: { resolver, arbiterProject, arbiterMetadata in
				let project = ProjectIdentifier.fromArbiter(arbiterProject)
				let pinnedVersion: PinnedVersion = arbiterMetadata.unbox

				guard let result = self.resolvedGitReference(project, pinnedVersion.commitish)
					.startOn(QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "org.carthage.CarthageKit.Resolver.selectedVersionForMetadata"))
					.first() else {
					return nil
				}

				let resolvedVersion = try? result.dematerialize()
				return resolvedVersion?.toArbiter()
			})
		
		do {
			let graph = try resolver.resolve()
			let resolved = ResolvedCartfile.fromArbiter(graph)
			return SignalProducer(values: resolved.dependencies)
		} catch let ex as ArbiterError {
			return SignalProducer(error: CarthageError.ResolverError(ex))
		} catch {
			// TODO: Use a better error message #ErrorType
			return SignalProducer(error: CarthageError.UnresolvedDependencies(cartfile.dependencies.map { $0.project.name }))
		}
	}
}
