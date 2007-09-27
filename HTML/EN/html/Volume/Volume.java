import java.awt.*;                      			// Import the GUI stuff
import java.lang.Integer;               			// Needed for Str->Int conversion
import java.io.*;
import java.net.*;

public class Volume extends java.applet.Applet {
    Label l;                            			// Label to display slider's val
    int value = 0, width = 0, min = 0, max = 0;
    String server, player, title, msg;
    byte[] msgbytes;
    OutputStream outstream;

    public void init() {
        setLayout (new GridLayout (2, 1, 0, 0));		// Set to GridLayout, 2 rows, 1 col

        value = (Integer.parseInt (getParameter("value")));	// Get & check PARAMs from HTML code
        if (value == 0) value = 1;
        width = (Integer.parseInt (getParameter("barwidth")));
        if (width == 0) width = 0;
        min = (Integer.parseInt (getParameter("min")));
        if (min == 0) min = 1;
        max = (Integer.parseInt (getParameter("max")));
        if (max == 0) max = 100;

	player = getParameter("player");
	title = getParameter("title");
                
        l = new Label (title + String.valueOf (value));		// Define label
        add (l);                         			// Add label
                                         			// Def and add scrollbar
        add (new Scrollbar (Scrollbar.HORIZONTAL, value, width, min, max));

	try {
		server=getDocumentBase().getHost();		// the IP of the SqueezeCenter
		Socket sd = new Socket(server, 1069,false);	// false == UDP
		outstream = sd.getOutputStream();
	} catch (IOException e) {
		System.exit(0);
	}

	msgbytes = new byte[256];
    }

    public boolean handleEvent (Event evt) {			// Handle scrollbar events
	if (evt.target instanceof Scrollbar) {			// If scrollbar event...
		int v = (int)((double)((Scrollbar)evt.target).getValue() 
			/ ((double)max - (double)width) 
			* 100.0);
		l.setText (title + String.valueOf (v));		// Update label text
            

		try {
			msg = "executecommand(" + 
				player + 
				", mixer, volume, " + 
				String.valueOf(v) +
				")"; 
			msg.getBytes(0,msg.length(), msgbytes, 0);
			outstream.write(msgbytes, 0, msg.length());
			outstream.flush();
		} catch (IOException e) {
			System.exit(0);
		}
	}
      return true;
   }
}



