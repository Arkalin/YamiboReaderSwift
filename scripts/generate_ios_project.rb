require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_dir = File.join(root, 'YamiboReaderIOS.xcodeproj')
project_path = File.join(project_dir, 'project.pbxproj')

FileUtils.rm_rf(project_dir)
project = Xcodeproj::Project.new(project_dir, false, 77)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2640'
project.root_object.attributes['LastUpgradeCheck'] = '2640'
project.root_object.attributes['BuildIndependentTargetsInParallel'] = '1'

app_target = project.new_target(:application, 'YamiboReaderIOS', :ios, '17.0')
app_target.product_name = 'YamiboReaderIOS'
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][app_target.uuid] = {
  'CreatedOnToolsVersion' => '26.4'
}

main_group = project.main_group
app_group = main_group.find_subpath('YamiboReaderIOS', true)
app_group.set_source_tree('<group>')

app_file = app_group.new_file('YamiboReaderIOS/YamiboReaderIOSApp.swift')
assets = app_group.new_file('YamiboReaderIOS/Assets.xcassets')
app_target.add_file_references([app_file])
app_target.resources_build_phase.add_file_reference(assets)

package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = '.'
project.root_object.package_references << package_ref

ui_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
ui_product.package = package_ref
ui_product.product_name = 'YamiboReaderUI'
app_target.package_product_dependencies << ui_product

target_dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
target_dependency.product_ref = ui_product
app_target.dependencies << target_dependency

framework_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
framework_build_file.product_ref = ui_product
app_target.frameworks_build_phase.files << framework_build_file

project.targets.each do |target|
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['DEVELOPMENT_TEAM'] = ''
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.arkalin.YamiboReaderIOS'
    settings['CURRENT_PROJECT_VERSION'] = '1'
    settings['MARKETING_VERSION'] = '1.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'YamiboReaderIOS'
    settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
    settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
    settings['INFOPLIST_KEY_UIStatusBarStyle'] = 'UIStatusBarStyleDefault'
    settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
    settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
    settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
    settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
    settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    settings['SDKROOT'] = 'auto'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['SUPPORTS_MACCATALYST'] = 'NO'
  end
end

project.save
puts "Created #{project_path}"
