import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DMASplitter::*;
import Serializer::*;
import DividedFIFO::*;

import define::*;
import DTW::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
    (HwMainIfc);

    SerializerIfc#(32, DivSize) serial_X <- mkSerializer;
    SerializerIfc#(32, DivSize) serial_Y <- mkSerializer;

    // DTW Init data Q
    FIFO#(Input_t) dtw_x_initQ <- mkFIFO;
    FIFO#(Input_t) dtw_y_initQ <- mkFIFO;

    // Input
    FIFO#(Input_t) x_inQ <- mkFIFO;
    FIFO#(Input_t) y_inQ <- mkFIFO;
    Vector#(Module_num, FIFO#(Input_t)) module_xQ <- replicateM(mkFIFO);
    Vector#(Module_num, FIFO#(Input_t)) module_yQ <- replicateM(mkFIFO);
    Vector#(Module_num, FIFO#(Output_t)) resultQ <- replicateM(mkFIFO);
    Reg#(Bit#(5)) input_handle <- mkReg(1);


    FIFO#(Output_t) outputQ <- mkFIFO;
    // For DTW first module
    DividedBRAMFIFOIfc#(Tuple4#(Input_t, Input_t, Output_t, Output_t), Window_Size, 20) first_mQ <- mkDividedBRAMFIFO;


    Vector#(Module_num,DTWIfc) dtw <- replicateM(mkDTW);
    /* DTWIfc dtw <- mkDTW; */

    Reg#(Bit#(16)) x_cnt <- mkReg(0);
    Reg#(Bit#(16)) y_cnt <- mkReg(0);
    Reg#(Bit#(16)) dtw_init_cnt <- mkReg(0);

    Vector#(Module_num, Reg#(Bit#(16))) window_cnt <- replicateM(mkReg(0));

    Reg#(Bit#(16)) total_cnt <- mkReg(1);

    Reg#(Bool) x_init_done <- mkReg(False);
    Reg#(Bool) y_init_done <- mkReg(False);
    Reg#(Bool) dtw_init_done <- mkReg(False);
    Reg#(Bool) x_in_finish <- mkReg(False);
    Reg#(Bool) y_in_finish <- mkReg(False);

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
            /* loo <= 1; */
        end else if ( off == 1 ) begin
            serial_Y.put(d);
        end else begin
            $display(" Write request err ");
        end
    endrule

    rule x_value_init(!x_init_done);
        Bit#(Input_Size) d <- serial_X.get;
        dtw_x_initQ.enq(unpack(d));

        if (x_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            x_init_done <= True;
        end
        x_cnt <= x_cnt + 1;
    endrule

    rule y_value_init(!y_init_done);
        Bit#(Input_Size) d <- serial_Y.get;
        dtw_y_initQ.enq(unpack(d));

        if (y_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            y_init_done <= True;
            outputQ.enq(0);
        end
        y_cnt <= y_cnt + 1;
    endrule

    rule x_value_control(x_init_done);
        Bit#(Input_Size) d = 0;
        d <- serial_X.get;
        x_inQ.enq(unpack(d));
    endrule

    rule y_value_control(y_init_done);
        Bit#(Input_Size) d = 0;
        d <- serial_Y.get;
        y_inQ.enq(unpack(d));
    endrule

    rule spread_to_module_x;
        Bit#(5) i = input_handle % fromInteger(valueof(Module_num));
        x_inQ.deq;
        y_inQ.deq;

        module_xQ[i].enq(x_inQ.first);
        module_yQ[i].enq(y_inQ.first);

        if (input_handle == fromInteger(valueof(Module_num)) - 1) begin
            input_handle <= 0;
        end else begin
            input_handle <= input_handle + 1;
        end
    endrule

    // dtw first module init
    rule dtw_first_init(!dtw_init_done);
        dtw_x_initQ.deq;
        dtw_y_initQ.deq;

        if (dtw_init_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            dtw_init_cnt <= 0;
            dtw_init_done <= True;
        end else begin
            dtw_init_cnt <= dtw_init_cnt + 1;
        end

        if (dtw_init_cnt == 0) begin
            first_mQ.enq(tuple4(dtw_x_initQ.first, dtw_y_initQ.first, 0, 0));
        end else begin
            first_mQ.enq(tuple4(dtw_x_initQ.first, dtw_y_initQ.first, 32767, 32767));
        end
    endrule

    rule first_dtw_module_input;
        first_mQ.deq;
        let d = first_mQ.first;
        dtw[0].put_d(d);
    endrule

    rule calculate_first_m(dtw_init_done);
        Tuple2#(Output_t, Output_t) d <- dtw[valueof(Module_num) - 1].get;
        Bit#(16) i = 0;
        Input_t x = 0;
        Input_t y = 0;
        if (window_cnt[i] == fromInteger(valueof(Window_Size)) - 1) begin
            module_xQ[i].deq;
            module_yQ[i].deq;
            x = module_xQ[i].first;
            y = module_yQ[i].first;
            window_cnt[i] <= 0;
        end else begin
            x <- dtw[valueof(Module_num) - 1].get_x;
            y <- dtw[valueof(Module_num) - 1].get_y;
            window_cnt[i] <= window_cnt[i] + 1;
        end
        if (window_cnt[i] == 0) begin
            resultQ[i].enq(tpl_1(d));
        end
        first_mQ.enq(tuple4(x, y, tpl_1(d), tpl_2(d)));
        /* $display("id = %d  th x res is %d y res is %d ", i,  tpl_1(d), tpl_2(d)); */
    endrule

    for (Bit#(16) i = 1; i < fromInteger(valueof(Module_num)) - 1; i = i + 1) begin

        rule calculate(i != fromInteger(valueof(Module_num)) - 1);
            Tuple2#(Output_t, Output_t) d <- dtw[i - 1].get;
            Input_t x = 0;
            Input_t y = 0;
            if (window_cnt[i] == fromInteger(valueof(Window_Size)) - 1) begin
                module_xQ[i].deq;
                module_yQ[i].deq;
                x = module_xQ[i].first;
                y = module_yQ[i].first;
                window_cnt[i] <= 0;
            end else begin
                x <- dtw[i - 1].get_x;
                y <- dtw[i - 1].get_y;
                window_cnt[i] <= window_cnt[i] + 1;
            end
            dtw[i].put_d(tuple4(x, y, tpl_1(d), tpl_2(d)));
            if (window_cnt[i] == 0) begin
                resultQ[i].enq(tpl_1(d));
            end
            /* $display("id = %d  th x res is %d y res is %d ", i,  tpl_1(d), tpl_2(d)); */
        endrule

    end

    rule calculate_last_m(dtw_init_done);
        Bit#(16) i = fromInteger(valueof(Module_num)) - 1;
        Tuple2#(Output_t, Output_t) d <- dtw[i - 1].get;
        Input_t x = 0;
        Input_t y = 0;
        if (window_cnt[i] == fromInteger(valueof(Window_Size)) - 1) begin
            module_xQ[i].deq;
            module_yQ[i].deq;
            x = module_xQ[i].first;
            y = module_yQ[i].first;
            window_cnt[i] <= 0;
        end else begin
            x <- dtw[i - 1].get_x;
            y <- dtw[i - 1].get_y;
            window_cnt[i] <= window_cnt[i] + 1;
        end
        if (window_cnt[i] == 0) begin
            resultQ[i].enq(tpl_1(d));
        end
        /* $display("id = %d and  th x res is %d y res is %d ", i,  tpl_1(d), tpl_2(d)); */
        dtw[i].put_d(tuple4(x, y, tpl_1(d), tpl_2(d)));
    endrule

    rule get_result;
        Bit#(16) i = total_cnt % fromInteger(valueof(Module_num));
        resultQ[i].deq;
        total_cnt <= total_cnt + 1;
        $display("cnt result is %d th and %d ",total_cnt, resultQ[i].first);
    endrule
endmodule
