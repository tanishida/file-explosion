require 'xcodeproj'

project_path = '/Users/hiroakinishida/Documents/file-explosion/file-explosion.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Add Swift Package
package_repo_url = "https://github.com/stasel/WebRTC.git"
pkg_ref = project.root_object.package_references.find { |pr| pr.repositoryURL == package_repo_url }
if pkg_ref.nil?
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = package_repo_url
  pkg_ref.requirement = {
    "kind" => "upToNextMajorVersion",
    "minimumVersion" => "113.0.0"
  }
  project.root_object.package_references << pkg_ref
end

# Add Product Dependency
pkg_dep = target.package_product_dependencies.find { |dp| dp.product_name == 'WebRTC' }
if pkg_dep.nil?
  pkg_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  pkg_dep.product_name = 'WebRTC'
  pkg_dep.package = pkg_ref
  target.package_product_dependencies << pkg_dep
end

project.save
