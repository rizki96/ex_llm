#!/usr/bin/env elixir

# Script to migrate from require Logger to alias ExLLM.Infrastructure.Logger

defmodule LoggerMigration do
  def run do
    lib_files = Path.wildcard("lib/**/*.ex")
    
    migrated_count = 0
    
    for file <- lib_files do
      content = File.read!(file)
      
      # Check if file uses require Logger
      if String.contains?(content, "require Logger") do
        # Skip if it's the Logger module itself
        unless String.contains?(file, "infrastructure/logger.ex") do
          new_content = content
          |> String.replace("require Logger", "alias ExLLM.Infrastructure.Logger")
          
          File.write!(file, new_content)
          IO.puts("Migrated: #{file}")
          migrated_count = migrated_count + 1
        end
      end
    end
    
    IO.puts("\nMigrated #{migrated_count} files")
  end
end

LoggerMigration.run()