// insertdylib adds (or removes) an LC_LOAD_WEAK_DYLIB load command in a thin
// 64-bit Mach-O. A weak load means the app still starts if the dylib is gone.
//
//	insertdylib [--remove] [--check] BINARY DYLIB_PATH
//
// The binary's code signature becomes invalid; re-sign it afterwards.
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"os"
)

const (
	mhMagic64       = 0xfeedfacf
	lcSegment64     = 0x19
	lcLoadDylib     = 0xc
	lcLoadWeakDylib = 0x80000018
	headerSize      = 32
)

var le = binary.LittleEndian

type loadCmd struct {
	off, cmd, size uint32
}

func main() {
	remove := flag.Bool("remove", false, "remove the load command instead of adding it")
	check := flag.Bool("check", false, "only report whether the load command is present (exit 0 yes, 3 no)")
	flag.Parse()
	if flag.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "usage: insertdylib [--remove] [--check] BINARY DYLIB_PATH")
		os.Exit(2)
	}
	bin, dylib := flag.Arg(0), flag.Arg(1)
	data, err := os.ReadFile(bin)
	if err != nil {
		fail(err)
	}
	if len(data) < headerSize || le.Uint32(data[0:]) != mhMagic64 {
		fail(fmt.Errorf("%s is not a thin 64-bit little-endian Mach-O (use lipo -thin first)", bin))
	}
	ncmds := le.Uint32(data[16:])
	sizeofcmds := le.Uint32(data[20:])

	var cmds []loadCmd
	minSection := uint32(len(data))
	present := -1
	off := uint32(headerSize)
	for i := uint32(0); i < ncmds; i++ {
		c := loadCmd{off: off, cmd: le.Uint32(data[off:]), size: le.Uint32(data[off+4:])}
		switch c.cmd {
		case lcLoadDylib, lcLoadWeakDylib:
			nameOff := le.Uint32(data[off+8:])
			name := data[off+nameOff : off+c.size]
			if i := bytes.IndexByte(name, 0); i >= 0 {
				name = name[:i]
			}
			if string(name) == dylib {
				present = len(cmds)
			}
		case lcSegment64:
			nsects := le.Uint32(data[off+64:])
			for s := uint32(0); s < nsects; s++ {
				so := off + 72 + s*80
				secOff := le.Uint32(data[so+48:])
				flags := le.Uint32(data[so+64:])
				typ := flags & 0xff
				if secOff != 0 && typ != 0x1 && typ != 0xc && typ != 0x12 && secOff < minSection {
					minSection = secOff
				}
			}
		}
		cmds = append(cmds, c)
		off += c.size
	}

	if *check {
		if present >= 0 {
			fmt.Println("present")
			return
		}
		fmt.Println("absent")
		os.Exit(3)
	}

	if *remove {
		if present < 0 {
			fmt.Println("not present; nothing to do")
			return
		}
		c := cmds[present]
		end := headerSize + sizeofcmds
		copy(data[c.off:], data[c.off+c.size:end])
		for i := end - c.size; i < end; i++ {
			data[i] = 0
		}
		le.PutUint32(data[16:], ncmds-1)
		le.PutUint32(data[20:], sizeofcmds-c.size)
		write(bin, data)
		fmt.Println("removed", dylib)
		return
	}

	if present >= 0 {
		fmt.Println("already present")
		return
	}
	pathLen := uint32(len(dylib) + 1)
	cmdsize := (24 + pathLen + 7) &^ 7
	start := headerSize + sizeofcmds
	if start+cmdsize > minSection {
		fail(fmt.Errorf("not enough room for the load command: %d bytes free, %d needed", minSection-start, cmdsize))
	}
	for i := start; i < start+cmdsize; i++ {
		if data[i] != 0 {
			fail(fmt.Errorf("header padding at %d is not empty", i))
		}
	}
	le.PutUint32(data[start:], lcLoadWeakDylib)
	le.PutUint32(data[start+4:], cmdsize)
	le.PutUint32(data[start+8:], 24)       // name offset
	le.PutUint32(data[start+12:], 2)       // timestamp
	le.PutUint32(data[start+16:], 0x10000) // current version 1.0.0
	le.PutUint32(data[start+20:], 0x10000) // compatibility version 1.0.0
	copy(data[start+24:], dylib)
	le.PutUint32(data[16:], ncmds+1)
	le.PutUint32(data[20:], sizeofcmds+cmdsize)
	write(bin, data)
	fmt.Printf("added LC_LOAD_WEAK_DYLIB %s (%d bytes of header padding left)\n", dylib, minSection-start-cmdsize)
}

func write(path string, data []byte) {
	fi, err := os.Stat(path)
	if err != nil {
		fail(err)
	}
	tmp := path + ".insertdylib"
	if err := os.WriteFile(tmp, data, fi.Mode()); err != nil {
		fail(err)
	}
	if err := os.Rename(tmp, path); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "insertdylib:", err)
	os.Exit(1)
}
