"""Create and remove only Certbot's own Alibaba Cloud DNS challenge record."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from alibabacloud_alidns20150109.client import Client
from alibabacloud_alidns20150109 import models
from alibabacloud_tea_openapi import models as openapi


ZONE = "itapgo.com"
STATE = Path("/var/lib/tapgo-relay/acme-challenges")
CREDENTIALS = Path("/etc/tapgo-relay/aliyun-dns.json")


def client():
    keys = json.loads(CREDENTIALS.read_text())
    return Client(openapi.Config(
        access_key_id=keys["accessKeyId"],
        access_key_secret=keys["accessKeySecret"],
        endpoint="alidns.cn-hangzhou.aliyuncs.com",
    ))


def challenge():
    domain = os.environ["CERTBOT_DOMAIN"].removeprefix("*.")
    if domain not in {"relay.itapgo.com", "remote.itapgo.com"}:
        raise ValueError("Unexpected Tapgo relay certificate domain")
    value = os.environ["CERTBOT_VALIDATION"]
    return f"_acme-challenge.{domain.removesuffix('.' + ZONE)}", value


def record_file(value):
    return STATE / hashlib.sha256(value.encode()).hexdigest()


def authenticate():
    rr, value = challenge()
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    record = client().add_domain_record(models.AddDomainRecordRequest(
        domain_name=ZONE, rr=rr, type="TXT", value=value, ttl=600,
    ))
    record_file(value).write_text(str(record.body.record_id))
    os.chmod(record_file(value), 0o600)
    name = f"{rr}.{ZONE}"
    for _ in range(36):
        answer = subprocess.run(
            ["/usr/bin/dig", "+short", "TXT", name, "@dns7.hichina.com"],
            check=True, capture_output=True, text=True,
        ).stdout
        if value in answer:
            time.sleep(20)
            return
        time.sleep(5)
    raise TimeoutError(f"DNS challenge did not propagate for {name}")


def cleanup():
    _, value = challenge()
    path = record_file(value)
    if not path.exists():
        return
    client().delete_domain_record(models.DeleteDomainRecordRequest(record_id=path.read_text().strip()))
    path.unlink()


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"auth", "cleanup"}:
        raise SystemExit("usage: certbot-alidns-hook.py auth|cleanup")
    (authenticate if sys.argv[1] == "auth" else cleanup)()
