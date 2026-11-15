const assert = require('node:assert/strict');
const {extract} = require('../ThreadsStudio/ThreadsScan.js');
function post(code,author,text,extra={}) {
  return {pk:code,code,user:{username:author},caption:{text},like_count:2,...extra};
}
const root = post('root','owner','Full caption',{carousel_media:[{image_versions2:{candidates:[{url:'small',width:10,height:10},{url:'first',width:800,height:800}]}},{image_versions2:{candidates:[{url:'second',width:800,height:800}]}}]});
const reply = post('reply','viewer','A long comment with all its words',{text_post_app_info:{is_reply:true,root_post_author:{username:'owner'},reply_to_author:{username:'owner'},is_liked_by_root_author:true,direct_reply_count:3}});
const back = post('back','owner','Thanks',{text_post_app_info:{is_reply:true,root_post_author:{username:'owner'},reply_to_author:{username:'viewer'}}});
const short = {...reply,caption:{text:'A long comment'}};
const unrelated = post('other','outsider','unrelated',{text_post_app_info:{is_reply:true,root_post_author:{username:'other'}}});
let result = extract([{thread_items:[{post:root}]},{thread_items:[{post:reply},{post:back}]},short,unrelated,{quoted_post:post('quoted','owner','quoted')}],'root');
assert.equal(result.root.text,'Full caption');assert.deepEqual(result.root.images,['first','second']);
assert.equal(result.comments.length,2);const comment = result.comments.find(x => x.id === 'reply');
assert.equal(comment.text,reply.caption.text);assert.equal(comment.authorReplied,true);assert.equal(comment.authorLiked,true);
assert.equal(comment.replies,3);
result = extract([root,reply],'root');assert.equal(result.comments[0].authorReplied,false);
assert.equal(extract([root],'missing'),null);
console.log('PASS: complete text, ordered images, thread boundary, author interaction evidence.');
