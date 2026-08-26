require_relative '../test_case'

class TestRepliesController < TestCase

  def before_suite
    ontologies = self.create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)[2]
    @@ontology = ontologies.first

    @@reply_user = "test_reply_user"
    @@user = LinkedData::Models::User.new(
      username: @@reply_user,
      email: "reply_user@example.org",
      password: "reply_user_pass"
    )
    @@user.save

    @@note = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject note",
      body: "Test body for note",
      relatedOntology: [@@ontology]
    })
    @@note.save

    @@note1 = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject note 1",
      body: "Test body for note 1",
      relatedOntology: [@@ontology]
    })
    @@note1.save

    @@replies = []
    5.times do |i|
      reply = LinkedData::Models::Notes::Reply.new({
        creator: @@user,
        body: "Test body for reply #{i}"
      })
      reply.save
      @@replies << reply
      @@note.reply = (@@note.reply || []).dup.push(reply)
      @@note.save
      @@note1.reply = (@@note.reply || []).dup.push(reply)
      @@note1.save
    end
  end

  def test_single_reply
    get @@note1.id.to_s
    replies = MultiJson.load(last_response.body)
    reply = replies["reply"].first
    get reply['@id']
    assert last_response.ok?
    retrieved_reply = MultiJson.load(last_response.body)
    assert_equal reply['@id'], retrieved_reply['@id']
  end

  def test_reply_lifecycle
    reply = {
      creator: @@user.id.to_s,
      body: "Testing body for reply",
      parent: @@note.id.to_s
    }
    post "/replies", MultiJson.dump(reply), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201

    new_reply = MultiJson.load(last_response.body)
    get new_reply["@id"]
    assert last_response.ok?

    reply_changes = {body: "New testing body"}
    patch new_reply["@id"], reply_changes.to_json, "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204
    get new_reply["@id"]
    patched_reply = MultiJson.load(last_response.body)
    assert_equal patched_reply["body"], reply_changes[:body]

    delete new_reply["@id"]
    assert last_response.status == 204
  end

  def test_delete_reply_removes_note_reference
    note = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Note for delete reference test",
      body: "Body for delete reference test",
      relatedOntology: [@@ontology]
    })
    note.save

    reply = LinkedData::Models::Notes::Reply.new({
      creator: @@user,
      body: "Reply to be deleted"
    })
    reply.save

    child = LinkedData::Models::Notes::Reply.new({
      creator: @@user,
      body: "Child of the deleted reply",
      parent: reply
    })
    child.save

    note.reply = (note.reply || []).dup.push(reply)
    note.save

    reply_id = reply.id
    child_id = child.id

    delete reply_id.to_s
    assert_equal 204, last_response.status

    # The reply and its child are gone
    assert_nil LinkedData::Models::Notes::Reply.find(reply_id).first
    assert_nil LinkedData::Models::Notes::Reply.find(child_id).first

    # The parent note no longer references the deleted reply
    note_after = LinkedData::Models::Note.find(note.id).include(:reply).first
    refute_includes (note_after.reply || []).map { |r| r.id }, reply_id

    note_after.delete
  end

  def test_delete_missing_reply_returns_404
    delete "/replies/does-not-exist"
    assert_equal 404, last_response.status
  end

end
