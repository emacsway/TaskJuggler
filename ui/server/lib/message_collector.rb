require 'taskjuggler/MessageHandler'

module MessageCollector
  def self.clear
    handler = TaskJuggler::MessageHandlerInstance.instance
    handler.clear if handler.respond_to?(:clear)
  rescue
    # MessageHandler may not support clear in all versions
  end

  def self.collect
    handler = TaskJuggler::MessageHandlerInstance.instance
    messages = []

    if handler.respond_to?(:messages)
      handler.messages.each do |msg|
        messages << {
          type: msg.type.to_s,
          id: msg.id.to_s,
          message: msg.message.to_s,
          file: msg.sourceFileInfo&.fileName,
          line: msg.sourceFileInfo&.lineNo,
          column: msg.sourceFileInfo&.columnNo
        }
      end
    end

    messages
  rescue => e
    [{ type: 'error', id: 'collector', message: "Failed to collect messages: #{e.message}",
       file: nil, line: nil, column: nil }]
  end
end
