

# naive code
Vector#(window_size - 1,Reg#(Bit#(element_size))) input_mem_r <- replicateM(mkReg(0));

rule get_data_row;
    // get one_element 
    in_buf_r.deq;
    Vector#(window_size, Bit#(element_size)) d = replicate(0);
    for (Bit#(8) i = 0; i < window_size - 1 ; i = i + 1) begin
        d[i] = input_mem_r[i];
    end
    d[window_size - 1] = in_buf_r.first;

    get_distant_rQ.enq(d);
    row_d.enq(d[window_size - 1]);

    for (Bit#(8) i = 0; i < window_size - 1; i = i + 1) begin
        input_mem_r[i] <= d[i + 1];
    end
endrule
// BRAM save
rule get_distant_r;
    get_distant_rQ.deq;
    col_d.deq;
    Bit#(element_size) col = col_d.first;
    Vector#(window_size, Bit#(element_size)) d = get_distant_rQ.first;

    for (Bit#(8) i = 0; i < window_size; i = i + 1) begin
        d = abs(d - col);
    end

    get_val_rQ.enq(d);
endrule
// window size >> BRAM (window > 10000 , col row > 30000)
rule get_val_r;
    pre_rQ.deq;
    get_val_rQ.deq;
    pre_element_rQ.deq;
    Bit#(element_size) pre_el = pre_element_rQ.first;
    Vector#(window_size, Bit#(element_size)) pre = pre_rQ.first;
    Vector#(window_size, Bit#(element_size)) cur = get_val_rQ.first;

    cur[0] = cur[0] + min(pre_el, pre[0], pre[1]);
    for (Bit#(8) i = 1 ; i < element_size - 1; i = i +1) begin
        cur[i] = cur[i] + min(cur[i - 1], pre[i] , pre[i + 1]);
    end
    cur[element_size - 1] = cur[element_size - 1] + min(cur[element_size - 2], pre[element_size -1]);

    pre_rQ.enq(cur);
    pre_element_cQ.enq(cur[1]);
endrule
