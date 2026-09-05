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
