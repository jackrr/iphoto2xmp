#!/usr/bin/env ruby
#
# Usage:
#   ruby export_albums.rb "~/Pictures/My iPhoto library" "~/Pictures/Export Here"
#
require 'sqlite3'
require 'fileutils'

indir = ARGV[0]
outdir = ARGV[1]

unless indir && outdir
  puts "Usage: #{$0} ~/Pictures/Photo\\ Library ~/Pictures/OutputDir"
  exit 1
end

def ensure_directory(path)
  File.directory?(path) || Dir.mkdir(path)
end


ensure_directory(outdir)

librarydb = SQLite3::Database.new("#{indir}/database/photos.db")
librarydb.results_as_hash = true

album_blacklist = ['Trash', 'Imports', 'Hidden', 'My Photo Stream', 'Unable to Upload', 'Events']

# 1. get all albums
albumhead, *albums = librarydb.execute2(
  "SELECT
    a.modelId as id,
    a.name as name,
    f.name as folder
    FROM RKAlbum a
    LEFT JOIN RKFolder f on a.folderUuid=f.uuid
  "
)
# 2. for each album
imported_albums = []
albums.each do |album|
  next if album['folder'] == 'mediaTypesFolder'
  next if !album['name']
  next if album_blacklist.include? album['name']
  imported_albums << album['id']

  # a. get all photos
  photohead, *photos = librarydb.execute2(
    "SELECT
      p.imagePath as path
      FROM RKAlbumVersion av
      LEFT JOIN RKVersion v ON av.versionId=v.modelId
      LEFT JOIN RKMaster p ON p.uuid=v.masterUuid
      WHERE av.albumId=#{album['id']}
    "
  )
  dest_components = [outdir]

  if album['folder']
    dest_components << album['folder'].gsub('/', '__')
    ensure_directory(File.join(dest_components))
  end

  dest_components << album['name'].gsub('/', '__')
  album_dir = File.join(dest_components)
  if File.directory?(album_dir)
    puts "Already imported #{album_dir}"
    next
  end
  ensure_directory(album_dir)

  # b. save photos to album directory
  num_copied = 0
  photos.each do |photo|
    src = File.join([indir, 'Masters', photo['path']])
    dest = File.join(album_dir, File.basename(src))
    next if File.exists?(dest) # save a lil time for revisions
    FileUtils.cp(src, dest)
    num_copied += 1
  end

  puts "#{album['name']}: #{num_copied} (#{album['folder']})"
end

# 3. get all photos
photohead, *photos = librarydb.execute2(
  "SELECT
    p.imagePath as path,
    av.albumId as albumId
    FROM RKVersion v
    LEFT JOIN RKMaster p ON p.uuid=v.masterUuid
    LEFT JOIN RKAlbumVersion av ON av.versionId=v.modelId
  "
)

num_defaults = 0
photos.each do |photo|
  # a. if not already in an album, save to catch-all
  next if imported_albums.include?(photo['albumId'])

  src = File.join([indir, 'Masters', photo['path']])
  dest_album = File.join([outdir, 'uncategorized'], File.dirname(photo['path']))

  FileUtils.mkdir_p(dest_album)

  FileUtils.cp(src, File.join(dest_album, File.basename(src)))
  num_defaults += 1
end

puts "Copied #{num_defaults} uncategorized photos"
