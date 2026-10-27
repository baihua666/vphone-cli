package com.vphone.research;

import com.licel.jcardsim.base.Simulator;
import com.licel.jcardsim.base.SimulatorRuntime;
import com.licel.jcardsim.remote.VSmartCardTCPProtocol;
import com.licel.jcardsim.samples.HelloWorldApplet;
import javacard.framework.AID;
import java.io.IOException;

// Compiled only by the VPHONE_EXPERIMENTAL_NFC_NO_RF build gate. No reloader/server.
public final class NFCNoRFCard {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("expected loopback port");
        int port = Integer.parseInt(args[0]);
        if (port < 1 || port > 65535) throw new IllegalArgumentException("invalid port");
        byte[] aid = new byte[] {(byte) 0xf0, 0x56, 0x50, 0x48, 0x4f, 0x4e, 0x45, 0x01};
        Simulator simulator = new Simulator(new SimulatorRuntime());
        simulator.installApplet(new AID(aid, (short) 0, (byte) aid.length), HelloWorldApplet.class);
        VSmartCardTCPProtocol wire = new VSmartCardTCPProtocol();
        wire.connect("127.0.0.1", port);
        try {
            while (true) {
                int command = wire.readCommand();
                switch (command) {
                    case VSmartCardTCPProtocol.RESET:
                    case VSmartCardTCPProtocol.POWER_ON:
                        simulator.reset();
                        break;
                    case VSmartCardTCPProtocol.GET_ATR:
                        wire.writeData(simulator.getATR());
                        break;
                    case VSmartCardTCPProtocol.APDU:
                        wire.writeData(simulator.transmitCommand(wire.readData()));
                        break;
                    default:
                        throw new IllegalArgumentException("unsupported control: " + command);
                }
            }
        } catch (IOException disconnected) {
            // The owner closes this ID-less stream on completion, timeout or removal.
        } finally {
            wire.disconnect();
        }
    }
}
