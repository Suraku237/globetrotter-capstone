import pytest
from fastapi import HTTPException

from app import social


@pytest.fixture
def social_store(tmp_path, monkeypatch):
    monkeypatch.setattr(social, "FRIENDSHIPS_FILE", tmp_path / "friendships.json")
    monkeypatch.setattr(social, "DIRECT_THREADS_FILE", tmp_path / "direct_threads.json")
    monkeypatch.setattr(social, "GROUPS_FILE", tmp_path / "chat_groups.json")
    users = [
        {
            "id": "alice",
            "full_name": "Alice Traveler",
            "username": "alice",
            "avatar_url": None,
        },
        {
            "id": "bob",
            "full_name": "Bob Explorer",
            "username": "bob",
            "avatar_url": None,
        },
    ]
    monkeypatch.setattr(social, "load_users", lambda: users)
    return users


def test_friendship_acceptance_enables_direct_messages(social_store):
    alice, bob = social_store

    created = social.send_friend_request(
        social.FriendRequestCreate(username="BOB"), current_user=alice
    )
    overview = social.get_friends(current_user=bob)
    assert overview["incoming_requests"][0]["user"]["username"] == "alice"

    social.accept_friend_request(created["request_id"], current_user=bob)
    overview = social.get_friends(current_user=alice)
    assert overview["friends"][0]["id"] == "bob"

    sent = social.send_direct_message(
        "bob", social.TextMessageCreate(text="Hello Bob"), current_user=alice
    )
    messages = social.get_direct_messages("alice", current_user=bob)
    assert messages == [sent]


def test_direct_messages_require_accepted_friendship(social_store):
    alice, _ = social_store

    with pytest.raises(HTTPException, match="after they accept"):
        social.send_direct_message(
            "bob", social.TextMessageCreate(text="Hello"), current_user=alice
        )


def test_group_requires_friends_and_all_members_can_message(social_store):
    alice, bob = social_store
    request = social.send_friend_request(
        social.FriendRequestCreate(username="bob"), current_user=alice
    )
    social.accept_friend_request(request["request_id"], current_user=bob)

    group = social.create_group(
        social.GroupCreate(name="Cameroon travelers", member_ids=["bob"]),
        current_user=alice,
    )
    sent = social.send_group_message(
        group["id"], social.TextMessageCreate(text="Welcome!"), current_user=bob
    )
    assert social.get_group_messages(group["id"], current_user=alice) == [sent]


def _accept(alice, bob):
    request = social.send_friend_request(
        social.FriendRequestCreate(username="bob"), current_user=alice
    )
    social.accept_friend_request(request["request_id"], current_user=bob)


def test_sticker_message_is_stored_with_sticker_id(social_store):
    alice, bob = social_store
    _accept(alice, bob)

    sent = social.send_direct_message(
        "bob",
        social.TextMessageCreate(type="sticker", sticker_id="party"),
        current_user=alice,
    )

    assert sent["type"] == "sticker"
    assert sent["sticker_id"] == "party"
    # Fallback text is present for older clients / notifications.
    assert sent["text"].startswith("[sticker:")


def test_unknown_sticker_is_rejected(social_store):
    alice, bob = social_store
    _accept(alice, bob)

    with pytest.raises(HTTPException, match="Unknown sticker"):
        social.send_direct_message(
            "bob",
            social.TextMessageCreate(type="sticker", sticker_id="not-a-real-sticker"),
            current_user=alice,
        )


def test_voice_message_requires_our_own_audio_url(social_store):
    alice, bob = social_store
    _accept(alice, bob)

    with pytest.raises(HTTPException, match="Invalid voice message URL"):
        social.send_direct_message(
            "bob",
            social.TextMessageCreate(
                type="voice",
                voice_url="https://evil.example.com/audio.mp3",
                voice_duration_ms=1500,
            ),
            current_user=alice,
        )


def test_voice_message_stores_url_and_duration(social_store):
    alice, bob = social_store
    _accept(alice, bob)

    sent = social.send_direct_message(
        "bob",
        social.TextMessageCreate(
            type="voice",
            voice_url="/audio/voice/alice_1.m4a",
            voice_duration_ms=2500,
        ),
        current_user=alice,
    )

    assert sent["type"] == "voice"
    assert sent["voice_url"] == "/audio/voice/alice_1.m4a"
    assert sent["voice_duration_ms"] == 2500


def test_voice_duration_must_be_positive_and_capped(social_store):
    alice, bob = social_store
    _accept(alice, bob)

    with pytest.raises(HTTPException, match="Invalid voice message duration"):
        social.send_direct_message(
            "bob",
            social.TextMessageCreate(
                type="voice",
                voice_url="/audio/voice/x.m4a",
                voice_duration_ms=0,
            ),
            current_user=alice,
        )
    with pytest.raises(HTTPException, match="Invalid voice message duration"):
        social.send_direct_message(
            "bob",
            social.TextMessageCreate(
                type="voice",
                voice_url="/audio/voice/x.m4a",
                voice_duration_ms=social.MAX_VOICE_DURATION_MS + 1,
            ),
            current_user=alice,
        )


def test_stickers_catalogue_is_non_empty_and_ids_are_unique(social_store):
    alice, _ = social_store
    result = social.list_stickers(current_user=alice)
    assert len(result) > 0
    ids = [item["id"] for item in result]
    assert len(ids) == len(set(ids))
    # Every entry needs the fields the client relies on.
    for item in result:
        assert item["id"] and item["emoji"] and item["label"]
