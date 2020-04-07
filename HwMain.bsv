import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DMASplitter::*;
import Serializer::*;

import define::*;
import DTW::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
    (HwMainIfc);

    SerializerIfc#(32, DivSize) serial_X <- mkSerializer;
    SerializerIfc#(32, DivSize) serial_Y <- mkSerializer;

    // FIFO for controlling X, Y data
    FIFO#(Input_t) x_saveQ <- mkSizedBRAMFIFO(valueof(Window_Size) + 5);
    FIFO#(Input_t) y_saveQ <- mkSizedBRAMFIFO(valueof(Window_Size) + 5);

    // FIFO for calculated value
    FIFO#(Output_t) past_xQ <- mkSizedBRAMFIFO(valueof(Window_Size) + 5);
    FIFO#(Output_t) past_yQ <- mkSizedBRAMFIFO(valueof(Window_Size) + 5);

    // Input
    FIFO#(Input_t) x_inQ <- mkFIFO;
    FIFO#(Input_t) y_inQ <- mkFIFO;

    FIFO#(Output_t) outputQ <- mkFIFO;

    DTWIfc dtw <- mkDTW;

    Reg#(Bit#(16)) x_cnt <- mkReg(0);
    Reg#(Bit#(16)) y_cnt <- mkReg(0);
    Reg#(Bit#(16)) past_cnt <- mkReg(0);
    Reg#(Bit#(16)) output_cnt <- mkReg(0);

    Reg#(Bool) x_init_done <- mkReg(False);
    Reg#(Bool) y_init_done <- mkReg(False);
    Reg#(Bool) past_init_done <- mkReg(False);

    rule sendToHost;
        let r <- pcie.dataReq;
        let a = r.addr;

        // lower 2 bits are always zero
        let offset = (a>>2);
        if ( offset == 0 ) begin 
            outputQ.deq;
            Output_t result = outputQ.first;
            pcie.dataSend(r, zeroExtend(pack(result)));
            $display(" Send result to HOST");
        end else begin
            $display(" Read request err ");
        end
    endrule

    rule receiveFromHost;
        let w <- pcie.dataReceive;
        let a = w.addr;
        let d = w.data;
        
        // PCIe IO is done at 4 byte granularities
        // lower 2 bits are always zero
        let off = (a>>2);
        if ( off == 0 ) begin
            serial_X.put(d);
        end else if ( off == 1 ) begin
            serial_Y.put(d);
        end else begin
            $display(" Write request err ");
        end
    endrule

    rule past_value_init(!past_init_done);
        past_cnt <= past_cnt + 1;

        past_xQ.enq(0);
        past_yQ.enq(0);

        if (past_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            past_init_done <= True;
        end
    endrule

    rule x_value_init(!x_init_done);
        Bit#(Input_Size) d <- serial_X.get;
        x_saveQ.enq(unpack(d));

        if (x_cnt == fromInteger(valueof(Window_Size)) - 2) begin
            x_init_done <= True;
            x_cnt <= 0;
        end else begin
            x_cnt <= x_cnt + 1;
        end
    endrule

    rule y_value_init(!y_init_done);
        Bit#(Input_Size) d <- serial_Y.get;
        y_saveQ.enq(unpack(d));

        if (y_cnt == fromInteger(valueof(Window_Size)) - 2) begin
            y_init_done <= True;
            y_cnt <= 0;
        end else begin
            y_cnt <= y_cnt + 1;
        end
    endrule

    rule x_value_control(x_init_done);
        x_saveQ.deq;
        Input_t d = x_saveQ.first;

        if (x_cnt == 0) begin
            Bit#(Input_Size) t <- serial_X.get;
            Input_t new_x = unpack(t);
            x_saveQ.enq(new_x);
            x_cnt <= x_cnt + 1;
        end else if (x_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            x_saveQ.enq(d);
            x_cnt <= 0;
        end else begin
            x_saveQ.enq(d);
            x_cnt <= x_cnt + 1;
        end

        x_inQ.enq(d);
    endrule

    rule y_value_control(y_init_done);
        y_saveQ.deq;
        Input_t d = y_saveQ.first;

        if (y_cnt == 0) begin
            Bit#(Input_Size) t <- serial_Y.get;
            Input_t new_y = unpack(t);
            y_saveQ.enq(new_y);
            y_cnt <= y_cnt + 1;
        end else if (y_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            y_saveQ.enq(d);
            y_cnt <= 0;
        end else begin
            y_saveQ.enq(d);
            y_cnt <= y_cnt + 1;
        end

        y_inQ.enq(d);
    endrule


    rule calculate;
        x_inQ.deq;
        y_inQ.deq;
        past_xQ.deq;
        past_yQ.deq;
        $display("x in is %d y in is %d ",x_inQ.first, y_inQ.first);
        dtw.put_d(tuple4(x_inQ.first, y_inQ.first, past_xQ.first, past_yQ.first));
    endrule

    rule get_d(past_init_done);
        Tuple2#(Output_t, Output_t) d <- dtw.get;
        past_xQ.enq(tpl_1(d));
        past_yQ.enq(tpl_2(d));
        $display("res is %d cnt is %d ",tpl_1(d),output_cnt);
        output_cnt <= output_cnt + 1;
    endrule
endmodule
