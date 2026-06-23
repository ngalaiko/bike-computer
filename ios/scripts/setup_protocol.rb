require 'xcodeproj'

project_path = File.expand_path('../Voop.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Voop' }
abort "Target 'Voop' not found" unless target

# Remove DataPoint.swift from Sources — it's now a placeholder comment
target.source_build_phase.files
  .select { |bf| bf.file_ref&.path == 'DataPoint.swift' }
  .each do |bf|
    bf.remove_from_project
    puts "  removed DataPoint.swift from Sources"
  end

# Add VoopProtocol.xcframework to Link Binary With Libraries
xcfw = 'VoopProtocol.xcframework'
unless target.frameworks_build_phase.files.any? { |bf| bf.file_ref&.path == xcfw }
  ref = project.main_group.files.find { |f| f.path == xcfw }
  unless ref
    ref = project.main_group.new_file(xcfw)
    ref.last_known_file_type = 'wrapper.xcframework'
  end
  target.frameworks_build_phase.add_file_reference(ref)
  puts "  added VoopProtocol.xcframework to Link Binary With Libraries"
end

# Add VoopProtocol.swift to Compile Sources
swift = 'voop_protocol.swift'
unless target.source_build_phase.files.any? { |bf| bf.file_ref&.path == swift }
  voop_group = project.main_group.find_subpath('Voop', false)
  abort "Could not find 'Voop' group in project" unless voop_group

  gen_group = voop_group.find_subpath('Generated', false) ||
              voop_group.new_group('Generated', 'Generated')

  ref = gen_group.files.find { |f| f.path == swift } || gen_group.new_file(swift)
  target.source_build_phase.add_file_reference(ref)
  puts "  added VoopProtocol.swift to Compile Sources"
end

project.save
puts "Xcode project saved."
