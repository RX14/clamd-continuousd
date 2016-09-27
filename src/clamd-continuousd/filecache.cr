module Clamd::Continuousd
  record FileInfo,
    path : String,
    modified : Time

  enum FileOperation
    Update
    Delete
  end

  class FileCache
    getter files : Hash(String, FileInfo)
    getter watched_directories : Array(String)

    @change_handler : FileOperation, FileInfo ->

    def initialize(@watched_directories, @change_handler)
      @files = Hash(String, FileInfo).new
    end

    # Watches directory for changes using inotify, and updates cache.
    def start_watching
      fd = LibInotify.inotify_init
      raise Errno.new("inotify_init") if fd < 0

      wd_dir = Hash(LibC::Int, String).new
      @watched_directories.each do |dir|
        wd = LibInotify.inotify_add_watch(fd, dir, LibInotify::IN_CLOSE_WRITE | LibInotify::IN_CREATE | LibInotify::IN_DELETE | LibInotify::IN_ONLYDIR)
        raise Errno.new("inotify_add_watch") if wd < 0

        wd_dir[wd] = dir
      end

      io = IO::FileDescriptor.new(fd)
      loop do
        event, name = read_inotify_event(io)
        path = File.join(wd_dir[event.wd], name)

        Continuousd.logger.debug "Recieved filesystem event for #{name}: #{event.inspect}", "fscache"

        case event.mask
        when LibInotify::IN_CLOSE_WRITE
        when LibInotify::IN_CREATE
          file_info = File.stat(path)
          update_file(path, file_info.mtime) if file_info.file?
        when LibInotify::IN_DELETE
          remove_file(path)
        end
      end
    end

    private def read_inotify_event(io)
      event = uninitialized LibInotify::Event
      io.read_fully(Slice(UInt8).new(pointerof(event).as(UInt8*), sizeof(LibInotify::Event)))

      name = String.new(event.len) do |buf|
        io.read_fully(Slice(UInt8).new(buf, event.len))

        # Remove padding null bytes from name
        (event.len.to_i - 1).downto(0) do |i|
          # Return previous index on first non-null byte
          break {i + 1, 0} unless buf[i] == 0

          # Return empty string if buf is completely null
          break {0, 0} if i == 0
        end.as({Int32, Int32})
      end

      {event, name}
    end

    def update_file(path, modified)
      file_info = FileInfo.new(path, modified)
      @files[path] = file_info
      @change_handler.call(FileOperation::Update, file_info)
    end

    def remove_file(path)
      file_info = @files.delete(path)
      @change_handler.call(FileOperation::Delete, file_info) if file_info
    end
  end
end
