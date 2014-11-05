require 'socket'

class ImapTestServer::Daemon
  include Common::Stoppable
  include Common::LightSleep
  include Common::WrappedThread
  include Common::DbConnection

  attr_accessor :port
  attr_accessor :connection_thread
  attr_accessor :new_sockets, :sockets, :socket_states
  attr_accessor :mailboxes

  def initialize(options = {})
    self.port = (options[:port] || 10143).to_i
    self.new_sockets = Queue.new
    self.sockets = []
    self.socket_states = {}
  end

  # Add the given Mail object to a user's inbox.
  def add_mail(mail)
    raise :todo
  end

  def run
    trap_signals
    start_connection_thread
    process_sockets
  rescue => e
    Log.exception(e)
    stop!
    raise e
  ensure
    connection_thread && connection_thread.terminate
    sockets.map(&:close)
  end

  private

  def start_connection_thread
    self.connection_thread = wrapped_thread do
      establish_db_connection
      connection_thread_runner
    end
  end

  def connection_thread_runner
    server = TCPServer.new(self.port)
    while running?
      begin
        Log.info("Waiting for connections.")
        socket = server.accept_nonblock
        new_sockets << socket
      rescue IO::EAGAINWaitReadable
        sleep 0.2
      end
    end
  end

  def process_sockets
    while running?
      process_new_sockets
      process_existing_sockets
    end
  end

  def process_new_sockets
    while !new_sockets.empty?
      socket = new_sockets.pop(true)
      process_new_socket(socket)
    end
  end

  def process_existing_sockets
    # Which sockets need attention?
    read_sockets, _, _ = IO.select(sockets)
    read_sockets.each do |socket|
      process_existing_socket(socket)
    end
  end

  def process_new_socket(socket)
    Log.info("Greeting the new socket.")

    # Say "Hi!"
    socket_state = ImapTestServer::SocketState.new(socket)
    socket_state.handle_connect

    # Add to our list of existing sockets.
    self.sockets << socket
    self.socket_states[socket.hash] = socket_state
  rescue => e
    Log.exception(e)
    close_socket(socket)
  end

  def process_existing_socket(socket)
    Log.info("Handling an existing socket.")

    command = socket.gets
    if command.present?
      socket_state.handle_command(command)
    else
      close_socket(socket)
    end
  rescue ImapTestServer::SocketState::ChaosDisconnect => e
    close_socket(socket)
  rescue => e
    Log.exception(e)
    close_socket(socket)
  end
end
