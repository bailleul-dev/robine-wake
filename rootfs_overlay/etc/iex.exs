use Toolshed

if RingLogger in Application.get_env(:logger, :backends, []) do
  IO.puts("RingLogger is collecting logs. Run ring_logger.attach to see them.")
end
