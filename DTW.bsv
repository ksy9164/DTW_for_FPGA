import FIFO::*;
import FIFOF::*;
import Vector::*;

import define::*;

import BRAM::*;
import BRAMFIFO::*;

interface DTWIfc;
    method Action put_d(Tuple4#(Input_t, Input_t, Output_t, Output_t) d);
    method ActionValue#(Tuple2#(Output_t, Output_t)) get;
    method ActionValue#(Input_t) get_x;
    method ActionValue#(Input_t) get_y;
endinterface

function Output_t min(Vector#(3,Output_t) past);
    if (past[0] <= past[1] && past[0] <= past[2]) begin
        return past[0];
    end else if (past[1] <= past[0] && past[1] <= past[2]) begin
        return past[1];
    end else begin
        return past[2];
    end
endfunction

(* synthesize *)
module mkDTW (DTWIfc);
    FIFO#(Tuple4#(Input_t, Input_t, Output_t, Output_t)) inQ <- mkFIFO;
    FIFO#(Tuple2#(Output_t, Output_t)) outputQ <- mkFIFO;
    FIFO#(Input_t) output_xQ <- mkFIFO;
    FIFO#(Input_t) output_yQ <- mkFIFO;

    Reg#(Bit#(2)) stage <- mkReg(0);
    Reg#(Bool) init_done <- mkReg(False);
    Reg#(Bool) x_init_done <- mkReg(False);
    Reg#(Bool) y_init_done <- mkReg(False);

    Reg#(Bit#(16)) x_stage <- mkReg(2);
    Reg#(Bit#(16)) y_stage <- mkReg(2);

    Reg#(Bit#(16)) input_cnt <- mkReg(0);

    Vector#(2, Reg#(Output_t)) y_past <- replicateM(mkReg(0));
    Vector#(2, Reg#(Output_t)) x_past <- replicateM(mkReg(0));

    Reg#(Input_t) x_static_val <- mkReg(0);
    Reg#(Input_t) y_static_val <- mkReg(0);

    FIFO#(Input_t) xQ <- mkSizedFIFO(5);
    FIFO#(Input_t) yQ <- mkSizedFIFO(5);

    FIFO#(Output_t) x_pastQ <- mkFIFO;
    FIFO#(Output_t) y_pastQ <- mkFIFO;

    FIFO#(Output_t) resQ <- mkFIFO;
    FIFO#(Output_t) x_resQ <- mkFIFO;
    FIFO#(Output_t) y_resQ <- mkFIFO;

    rule get_intput;
        inQ.deq;
        Input_t x = tpl_1(inQ.first);
        Input_t y = tpl_2(inQ.first);
        Output_t past_x = tpl_3(inQ.first);
        Output_t past_y = tpl_4(inQ.first);
        if (input_cnt != 0) begin
            output_xQ.enq(x);
            output_yQ.enq(y);
        end
        if (input_cnt == fromInteger(valueof(Window_Size)) - 1) begin
            input_cnt <= 0;
        end else begin
            input_cnt <= input_cnt + 1;
        end
        xQ.enq(x);
        yQ.enq(y);
        x_pastQ.enq(past_x);
        y_pastQ.enq(past_y);
    endrule

    rule init(stage == 0 && !x_init_done && !y_init_done);
        xQ.deq;
        yQ.deq;
        x_pastQ.deq;
        y_pastQ.deq;

        Input_t x = xQ.first;
        Input_t y = yQ.first;
        Output_t past_x = x_pastQ.first;

        x_past[0] <= past_x;
        x_static_val <= x;
        y_static_val <= y;
        stage <= stage + 1;
    endrule

    rule get_first_d(stage == 1 && !x_init_done && !y_init_done);
        x_pastQ.deq;
        y_pastQ.deq;

        Output_t past_x = x_pastQ.first;
        Output_t past_y = y_pastQ.first;
        
        Vector#(3, Output_t)past = replicate(0);
        past[0] = past_x;
        past[1] = past_y;
        past[2] = x_past[0];

        Output_t res = 0;
        if (x_static_val > y_static_val) begin
            res = zeroExtend(x_static_val - y_static_val) + min(past);
        end else begin
            res = zeroExtend(y_static_val - x_static_val) + min(past);
        end

        x_past[1] <= past_x;
        y_past[1] <= past_y;

        resQ.enq(res);
        stage <= stage + 1;
    endrule

    rule res_ctl(stage == 2 && !x_init_done && !y_init_done);
        resQ.deq;
        Output_t d = resQ.first;

        x_past[0] <= d;
        y_past[0] <= d;

        x_init_done <= True;
        y_init_done <= True;
        x_resQ.enq(d);
        y_resQ.enq(d);
        stage <= 0;
    endrule

    rule cal_x_data(x_init_done && x_stage < fromInteger(valueof(Window_Size)));
        x_pastQ.deq;
        xQ.deq;

        Input_t x_val = xQ.first;
        Vector#(3, Output_t)past = replicate(0);
        past[0] = x_past[0];
        past[1] = x_past[1];
        past[2] = x_pastQ.first;

        Output_t res = 0;
        if (x_val > y_static_val) begin
            res = zeroExtend(x_val - y_static_val) + min(past);
        end else begin
            res = zeroExtend(y_static_val - x_val) + min(past);
        end

        x_past[0] <= res;
        x_past[1] <= past[2];
        x_resQ.enq(res);
        x_stage <= x_stage + 1;
        /* output_xQ.enq(x_val); */
    endrule

    rule cal_last_x_data(x_init_done && x_stage == fromInteger(valueof(Window_Size)));
        xQ.deq;
        Input_t x_val = xQ.first;

        Output_t res = 0;

        if (x_past[0] > x_past[1]) begin
            if (x_val > y_static_val) begin
                res = x_past[1] + zeroExtend(x_val - y_static_val);
            end else begin
                res = x_past[1] + zeroExtend(y_static_val - x_val);
            end
        end else begin
            if (x_val > y_static_val) begin
                res = x_past[0] + zeroExtend(x_val - y_static_val);
            end else begin
                res = x_past[0] + zeroExtend(y_static_val - x_val);
            end
        end

        x_stage <= 2;
        x_init_done <= False;
        x_resQ.enq(res);
        /* output_xQ.enq(x_val); */
    endrule

    rule cal_y_data(y_init_done && y_stage < fromInteger(valueof(Window_Size)));
        y_pastQ.deq;
        yQ.deq;

        Input_t y_val = yQ.first;
        Vector#(3, Output_t)past = replicate(0);
        past[0] = y_past[0];
        past[1] = y_past[1];
        past[2] = y_pastQ.first;

        Output_t res = 0;
        if (y_val > x_static_val) begin
            res = zeroExtend(y_val - x_static_val) + min(past);
        end else begin
            res = zeroExtend(x_static_val - y_val) + min(past);
        end

        y_past[0] <= res;
        y_past[1] <= past[2];
        y_resQ.enq(res);
        /* output_yQ.enq(y_val); */
        y_stage <= y_stage + 1;
    endrule

    rule cal_last_y_data(y_init_done && y_stage == fromInteger(valueof(Window_Size)));
        yQ.deq;
        Input_t y_val = yQ.first;

        Output_t res = 0;

        if (y_past[0] > y_past[1]) begin
            if (y_val > x_static_val) begin
                res = y_past[1] + zeroExtend(y_val - x_static_val);
            end else begin
                res = y_past[1] + zeroExtend(x_static_val - y_val);
            end
        end else begin
            if (y_val > x_static_val) begin
                res = y_past[0] + zeroExtend(y_val - x_static_val);
            end else begin
                res = y_past[0] + zeroExtend(x_static_val - y_val);
            end
        end

        y_stage <= 2;
        y_init_done <= False;
        /* output_yQ.enq(y_val); */
        y_resQ.enq(res);
    endrule

    rule merge_result;
        x_resQ.deq;
        y_resQ.deq;

        outputQ.enq(tuple2(x_resQ.first, y_resQ.first));
    endrule

    method Action put_d(Tuple4#(Input_t, Input_t, Output_t, Output_t) d);
        inQ.enq(d);
    endmethod 
    method ActionValue#(Tuple2#(Output_t, Output_t)) get;
        outputQ.deq;
        return outputQ.first;
    endmethod
    method ActionValue#(Input_t) get_x;
        output_xQ.deq;
        return output_xQ.first;
    endmethod
    method ActionValue#(Input_t) get_y;
        output_yQ.deq;
        return output_yQ.first;
    endmethod
endmodule

