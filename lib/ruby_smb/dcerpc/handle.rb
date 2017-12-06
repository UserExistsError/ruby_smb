module RubySMB
  module Dcerpc
    class Handle

      attr_accessor :pipe
      attr_accessor :last_msg
      attr_accessor :msg_type
      attr_accessor :response

      def initialize(named_pipe)
        @pipe = named_pipe
      end

      def bind(endpoint:)
        ioctl_request(RubySMB::Dcerpc::Bind.new(endpoint: endpoint))
      end

      def request(opnum:, stub:, options:{})
        @msg_type = :request
        ioctl_request(
            RubySMB::Dcerpc::Request.new(
                opnum: opnum,
                stub: stub.new(options).to_binary_s
            )
        )
      end

      def ioctl_request(action, options={})
        request = @pipe.set_header_fields(RubySMB::SMB2::Packet::IoctlRequest.new(options))
        request.ctl_code = 0x0011C017
        request.flags.is_fsctl = 0x00000001
        request.buffer = action.to_binary_s
        @last_msg = @pipe.tree.client.send_recv(request)
        handle_msg(RubySMB::SMB2::Packet::IoctlResponse.read(@last_msg))
      end

      def handle_msg(msg)
        if @msg_type == :request
          dcerpc_response_stub = RubySMB::Dcerpc::Response.read(msg.buffer.to_binary_s).stub
          @response = dcerpc_response_stub.to_binary_s
        end
      end
    end
  end
end
