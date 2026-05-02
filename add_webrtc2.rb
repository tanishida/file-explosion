require 'xcodeproj'
project_path = '/Users/hiroakinishida/Documents/file-explosion/file-explosion.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Double check if WebRTC is added
pkg_dep = target.package_product_dependencies.find { |dp| dp.product_name == 'WebRTC' }
puts "WebRTC package found? #{!pkg_dep.nil?}"

