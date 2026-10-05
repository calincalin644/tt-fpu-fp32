`timescale 1ns/1ps
module pins_tb;
    reg clk=0, rst_n=0, ena=1;
    always #5 clk=~clk;
    reg [7:0] ui=0, controls=0;
    wire [7:0] out, status, oe;
    tt_um_calincalin644_fpu_fp32 dut(ui,out,controls,status,oe,ena,clk,rst_n);
    reg req=0;
    reg [7:0] byte_read;
    integer fd, rc, count=0, op, rm, wanted_flags, i;
    reg [31:0] a,b,f,wanted,got;
    string path;
    task automatic transfer(input [3:0] address, input reading,
                            input [7:0] data, output [7:0] response);
        integer cycles;
        begin
            // Bundled data/control settle BEFORE the asynchronous request edge.
            @(negedge clk); #1;
            ui=data; controls={2'b0,address,reading,req};
            #2; req=~req; controls[0]=req;
            cycles=0;
            while (status[6] !== req && cycles<12) begin
                @(posedge clk); #1; cycles=cycles+1;
            end
            if (status[6] !== req) $fatal(1,"ACK timeout");
            if (cycles<2) $fatal(1,"Request bypassed synchronizer");
            if (oe !== 8'hc0 || status[5:0] !== 0) $fatal(1,"Pin directions/unused outputs");
            response=out;
        end
    endtask
    task automatic write_byte(input [3:0] address, input [7:0] data);
        reg [7:0] dummy;
        begin transfer(address,0,data,dummy); end
    endtask
    task automatic read_byte(input [3:0] address, output [7:0] data);
        begin transfer(address,1,0,data); end
    endtask
    task automatic write_word(input [3:0] base, input [31:0] word_value);
        integer j;
        begin for(j=0;j<4;j=j+1) write_byte(base+j,word_value[8*j +:8]); end
    endtask
    task automatic wait_done;
        integer polls;
        reg [7:0] value;
        begin
            value=0; polls=0;
            while (!value[1] && polls<400) begin read_byte(14,value); polls=polls+1; end
            if (!value[1] || value[0] || status[7]) $fatal(1,"Completion timeout/busy");
        end
    endtask
    task automatic reset_bus;
        begin
            @(negedge clk); rst_n=0; controls=0; req=0;
            repeat (4) @(posedge clk);
            @(negedge clk); rst_n=1;
            read_byte(14,byte_read);
            if (byte_read!==0) $fatal(1,"Reset status");
        end
    endtask
    initial begin
        if (!$value$plusargs("vectors=%s",path)) $fatal(1,"Missing vectors");
        fd=$fopen(path,"r"); if (!fd) $fatal(1,"Missing vector file");
        reset_bus();
        read_byte(15,byte_read); if(byte_read!==8'hf1) $fatal(1,"ID");
        write_byte(8,0); read_byte(14,byte_read); if(byte_read!==4) $fatal(1,"Invalid command 0");
        write_byte(14,0); read_byte(14,byte_read); if(byte_read!==0) $fatal(1,"Clear status");
        write_byte(8,8'hc1); read_byte(14,byte_read); if(byte_read!==4) $fatal(1,"Reserved command bits");
        write_byte(14,0);
        write_byte(9,0); read_byte(14,byte_read); if(byte_read!==4) $fatal(1,"Write readonly register");
        write_byte(14,0);
        // Deferred completion, write protection, and no lost sticky error.
        write_word(0,32'h3f800000); write_word(4,32'h40400000); write_byte(8,4);
        write_byte(0,8'hff); wait_done();
        read_byte(14,byte_read); if(byte_read!==6) $fatal(1,"Busy write not rejected");
        read_byte(0,byte_read); if(byte_read!==0) $fatal(1,"Busy write mutated operand");
        for (i=0;i<4;i=i+1) begin read_byte(9+i,byte_read); got[8*i +:8]=byte_read; end
        if(got!==32'h3eaaaaab) $fatal(1,"Busy write affected arithmetic");
        write_byte(14,0);
        // Reset and ena abort an in-flight operation; host restarts req at zero.
        write_byte(8,4); reset_bus();
        write_word(0,32'h3f800000); write_word(4,32'h40400000); write_byte(8,4);
        @(negedge clk); ena=0; controls=0; req=0;
        repeat(4) @(posedge clk);
        @(negedge clk); ena=1;
        read_byte(14,byte_read); if(byte_read!==0) $fatal(1,"ena abort status");
        read_byte(9,byte_read); if(byte_read!==0) $fatal(1,"ena abort result");
        while (!$feof(fd)) begin
            rc=$fscanf(fd,"%d %d %h %h %h %h %h\n",op,rm,a,b,f,wanted,wanted_flags);
            if(rc!=7) $fatal(1,"Malformed vector");
            write_word(0,op==5 ? f : a); write_word(4,b);
            write_byte(8,(rm<<3)|op);
            wait_done();
            for(i=0;i<4;i=i+1) begin read_byte(9+i,byte_read); got[8*i +:8]=byte_read; end
            if(got!==wanted) $fatal(1,"Vector %0d op=%0d rm=%0d got=%h expected=%h",count,op,rm,got,wanted);
            read_byte(13,byte_read); if(byte_read!==wanted_flags[7:0]) $fatal(1,"Flags vector %0d",count);
            read_byte(14,byte_read); if(byte_read!==2) $fatal(1,"Done/error status");
            // Holding request high or low indefinitely must not repeat a transfer.
            repeat(8) @(posedge clk);
            #1; if(out!==2 || status[6]!==req || status[7]!==0) $fatal(1,"Held request");
            count=count+1;
        end
        $display("PASS: %0d pin-level arithmetic vectors plus protocol/reset/ena checks",count);
        $finish;
    end
    initial begin #1000000000; $fatal(1,"Pin test timeout"); end
endmodule
