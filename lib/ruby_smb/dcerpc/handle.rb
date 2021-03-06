module RubySMB
  module Dcerpc
    class Handle

      attr_accessor :pipe
      attr_accessor :last_msg
      attr_accessor :response

      PTYPES = [
          RubySMB::Dcerpc::Request,
          nil,
          RubySMB::Dcerpc::Response
      ]

      # @param [RubySMB::SMB2::File] named_pipe
      # @return [RubySMB::Dcerpc::Handle]
      def initialize(named_pipe)
        @pipe = named_pipe
      end

      # @param [Class] endpoint
      def bind(options={})
        ioctl_request(RubySMB::Dcerpc::Bind.new(options))
      end

      # @param [Hash] options
      def request(opnum:, stub:, options:{})
        ioctl_request(
            RubySMB::Dcerpc::Request.new(
                opnum: opnum,
                stub: stub.new(options).to_binary_s
            )
        )
      end

      # @param [BinData::Record] action
      # @param [Hash] options
      def ioctl_request(action, options={})
        request = @pipe.set_header_fields(RubySMB::SMB2::Packet::IoctlRequest.new(options))
        request.ctl_code = 0x0011C017
        request.flags.is_fsctl = 0x00000001
        request.buffer = action.to_binary_s
        @last_msg = @pipe.tree.client.send_recv(request)
        handle_msg(RubySMB::SMB2::Packet::IoctlResponse.read(@last_msg))
      end

      # @param [BinData::Record] msg
      def handle_msg(msg)
        data = msg.buffer.to_binary_s
        headz = RubySMB::Dcerpc::PduHeader.read(data)
        pdu = PTYPES[headz.ptype]
        if pdu
          dcerpc_response_stub = pdu.read(msg.output_data).stub
          @response = dcerpc_response_stub.to_binary_s
        end
        data
      end
    end
  end
end
