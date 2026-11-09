from host import proto


def test_version_response_literal() -> None:
    assert proto.VERSION_RESPONSE == bytes.fromhex("560100010001")


def test_command_bytes_are_ascii() -> None:
    assert [chr(c) for c in (proto.CMD_VERSION, proto.CMD_RESET, proto.CMD_LOAD,
                             proto.CMD_STEP, proto.CMD_RUN, proto.CMD_ABORT,
                             proto.CMD_DUMP)] == list("VXLSRAD")
    assert chr(proto.RESP_OK) == "K" and chr(proto.RESP_ERR) == "E"


def test_headers_do_not_collide() -> None:
    assert proto.DUMP_HEADER not in (proto.VERSION_HEADER, proto.RESP_OK, proto.RESP_ERR)


def test_load_timeout_grows_with_n() -> None:
    assert proto.timeout_load_final_s(0) == 0.2
    assert abs(proto.timeout_load_final_s(256) - (0.2 + 0.089088)) < 1e-9
