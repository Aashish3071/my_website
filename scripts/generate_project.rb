# Rebuilds AuraDrive.xcodeproj from the source folders.
# Usage: gem install xcodeproj && ruby scripts/generate_project.rb "$PWD"
# Run it after adding, moving or deleting source files outside Xcode.
require 'xcodeproj'
root = ARGV[0]
proj_path = File.join(root, 'AuraDrive.xcodeproj')
FileUtils.rm_rf(proj_path)
project = Xcodeproj::Project.new(proj_path)
ios = '17.0'
app  = project.new_target(:application, 'AuraDrive', :ios, ios)
unit = project.new_target(:unit_test_bundle, 'AuraDriveTests', :ios, ios)
ui   = project.new_target(:ui_test_bundle, 'AuraDriveUITests', :ios, ios)
unit.add_dependency(app)
ui.add_dependency(app)

# Drop default framework refs the gem adds (SwiftUI links implicitly)
[app, unit, ui].each do |t|
  t.frameworks_build_phase.files.to_a.each { |f| f.remove_from_project }
end
project.files.select { |f| f.path.to_s.end_with?('.framework') }.each(&:remove_from_project)
fw = project.frameworks_group
fw.remove_from_project if fw && fw.children.empty?

def add_dir(group, dir, src_targets, res_target, &blk)
  Dir.children(dir).sort.each do |name|
    next if name.start_with?('.')
    path = File.join(dir, name)
    if name.end_with?('.xcassets')
      res_target.resources_build_phase.add_file_reference(group.new_reference(name))
    elsif File.directory?(path)
      add_dir(group.new_group(name, name), path, src_targets, res_target, &blk)
    elsif name.end_with?('.swift')
      ref = group.new_reference(name)
      targets = src_targets.dup
      blk.call(name, targets) if blk
      targets.each { |t| t.source_build_phase.add_file_reference(ref) }
    end
  end
end

shared = ['AccessibilityIdentifiers.swift']
add_dir(project.main_group.new_group('AuraDrive', 'AuraDrive'), File.join(root, 'AuraDrive'), [app], app) do |name, targets|
  targets << ui if shared.include?(name)
end
add_dir(project.main_group.new_group('AuraDriveTests', 'AuraDriveTests'), File.join(root, 'AuraDriveTests'), [unit], unit)
add_dir(project.main_group.new_group('AuraDriveUITests', 'AuraDriveUITests'), File.join(root, 'AuraDriveUITests'), [ui], ui)
project.main_group.children.move(project.products_group, project.main_group.children.count - 1) rescue nil

common = {
  'SWIFT_VERSION' => '6.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => ios,
  'TARGETED_DEVICE_FAMILY' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => '',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'MARKETING_VERSION' => '0.1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}
settings = {
  app => common.merge(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.yourcompany.auradrive',
    # Merged with the generated Info.plist; holds the Bluetooth background mode.
    'INFOPLIST_FILE' => 'AuraDrive/Info.plist',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS' => 'NO',
    'ENABLE_PREVIEWS' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
    'INFOPLIST_KEY_CFBundleDisplayName' => 'AuraDrive',
    'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.lifestyle',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone' =>
      'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription' =>
      'AuraDrive uses Bluetooth to connect to and control your car fragrance diffuser.',
  ),
  unit => common.merge(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.yourcompany.auradrive.tests',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/AuraDrive.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/AuraDrive',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
  ),
  ui => common.merge(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.yourcompany.auradrive.uitests',
    'TEST_TARGET_NAME' => 'AuraDrive',
  ),
}
settings.each do |t, s|
  t.build_configurations.each do |c|
    c.build_settings.delete('INFOPLIST_FILE')
    c.build_settings.merge!(s)
  end
end
project.build_configurations.each do |c|
  c.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios
  c.build_settings['SWIFT_VERSION'] = '6.0'
end

ro = project.root_object
ro.development_region = 'en'
ro.known_regions = ['en', 'Base']
ro.attributes['LastUpgradeCheck'] = '1600'
ro.attributes['LastSwiftUpdateCheck'] = '1600'
ro.attributes['TargetAttributes'] = {
  app.uuid => { 'CreatedOnToolsVersion' => '16.0' },
  unit.uuid => { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid },
  ui.uuid => { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid },
}
project.main_group.children.select { |g| g.display_name == 'Frameworks' && g.children.empty? }.each(&:remove_from_project)
project.instance_variable_set(:@object_version, '56')
ro.compatibility_version = 'Xcode 14.0'
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit)
scheme.add_test_target(ui)
scheme.save_as(proj_path, 'AuraDrive', true)
puts 'generated'
