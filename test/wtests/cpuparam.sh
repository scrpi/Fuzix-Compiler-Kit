
case "x"$1 in
	x6303)
		CPU=6303
		LINK=ld6800
		LIB=6800
		LINKOPT="-C256 -Z64"
		EMU="emu6800 6303"
		break
		;;
	x6502)
		CPU=6502
		LINK=ld6502
		LIB=6502
		LINKOPT="-C512 -Z0"
		EMU=emu6502
		break
		;;
	x65c02)
		CPU=65c02
		LINK=ld6502
		LIB=6502
		LINKOPT="-C512 -Z0"
		EMU=emu65c816
		break
		;;
	x65c816)
		CPU=65c816
		LINK=ld6502
		LIB=65c816
		LINKOPT="-C512"
		EMU=emu65c816
		break
		;;
	x6800)
		CPU=6800
		LINK=ld6800
		LIB=6800
		LINKOPT="-C256 -Z0"
		EMU="emu6800 6800"
		break
		;;
	x6803)
		CPU=6803
		LINK=ld6800
		LIB=6803
		LINKOPT="-C256 -Z64"
		EMU="emu6800 6803"
		break
		;;
	x6809)
		CPU=6809
		LINK=ld6809
		LIB=6809
		LINKOPT=-C256
		EMU=emu6809
		break
		;;
	x8070)
		CPU=8070
		LINK=ld8070
		LIB=8070
		LINKOPT="-C1 -Z0xFF00"
		EMU=emu807x
		break
		;;
	x8080)
		CPU=8080
		LINK=ld8080
		LIB=8080
		LINKOPT="-C256"
		EMU=emu85
		break
		;;
	x8085)
		CPU=8085
		LINK=ld8080
		LIB=8085
		LINKOPT="-C256"
		EMU=emu85
		break
		;;
	x68hc11)
		CPU=68hc11
		LINK=ld6800
		LIB=hc11
		LINKOPT=-C32768
		EMU="emu6800 6811"
		break
		;;
	xee200)
		CPU=ee200
		LINK=ldee200
		LIB=ee200
		LINKOPT=-C256
		EMU="ee200"
		break
		;;
	xhc11)
		CPU=68hc11
		LINK=ld6800
		LIB=hc11
		LINKOPT=-C32768
		EMU="emu6800 6811"
		break
		;;
	xsm83)
		CPU=sm83
		LINK=ldsm83
		LIB=sm83
		LINKOPT=-C0
		EMU="emusm83"
		break
		;;
	xtms7000)
		CPU=tms7000
		LINK=ld7000
		LIB=tms7000
		LINKOPT="-C0x200"
		EMU=emu7k
		break
		;;
	xz80)
		CPU=z80
		LINK=ldz80
		LIB=z80
		LINKOPT="-C0"
		EMU=emuz80
		break
		;;
	xz8)
		CPU=z8
		LINK=ldz8
		LIB=z8
		LINKOPT="-C0 -Z48"
		EMU=emuz8
		break
		;;
	*)
		echo "Unknown processor"
		exit 1
		;;
esac

if [ x"$2" != x ]; then
	OPT=$2
fi

