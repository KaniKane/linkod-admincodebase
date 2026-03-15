const firebase = require('@firebase/testing');
const functions = require('firebase-functions-test');
const admin = require('firebase-admin');

// Initialize Firebase Functions test
const projectId = 'linkod-db-test';
const testEnv = functions({
  projectId: projectId,
}, './serviceAccountKey.json');

// Test data
const USER_A = {
  uid: 'user_a_123',
  displayName: 'User A',
  fcmTokens: ['token_user_a_1', 'token_user_a_2']
};

const USER_B = {
  uid: 'user_b_456',
  displayName: 'User B',
  fcmTokens: ['token_user_b_1']
};

const PRODUCT = {
  id: 'product_123',
  sellerId: USER_A.uid,
  title: 'Test Product'
};

const POST = {
  id: 'post_456',
  userId: USER_A.uid,
  content: 'Test post'
};

describe('Cloud Functions Notification Triggers', () => {
  let adminStub;
  let sendMulticastStub;

  beforeAll(async () => {
    // Initialize admin app
    adminStub = admin.initializeApp({
      projectId: projectId,
      credential: admin.credential.applicationDefault()
    });
  });

  afterAll(() => {
    testEnv.cleanup();
    adminStub.delete();
  });

  beforeEach(() => {
    // Mock sendMulticast for each test
    sendMulticastStub = jest.fn().mockResolvedValue({
      successCount: 1,
      failureCount: 0
    });
    
    // Mock admin.messaging().sendMulticast
    jest.spyOn(admin.messaging(), 'sendMulticast').mockImplementation(sendMulticastStub);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('onProductReplyCreated', () => {
    it('should send FCM push when reply is created', async () => {
      // Import the function
      const { onProductReplyCreated } = require('../functions/index.js');

      // Create test data
      const parentMessageId = 'msg_parent_789';
      const replyMessageId = 'msg_reply_abc';
      
      // Mock parent message data
      const parentMessageData = {
        senderId: USER_A.uid,
        senderName: USER_A.displayName,
        message: 'Original message'
      };

      // Mock reply message data
      const replyMessageData = {
        senderId: USER_B.uid,
        senderName: USER_B.displayName,
        message: 'This is a reply',
        parentId: parentMessageId
      };

      // Create snapshot and context
      const snap = testEnv.firestore.makeDocumentSnapshot(
        replyMessageData,
        `products/${PRODUCT.id}/messages/${replyMessageId}`
      );
      
      const context = {
        params: {
          productId: PRODUCT.id,
          messageId: replyMessageId
        }
      };

      // Mock parent message document
      const parentDocRef = admin.firestore()
        .doc(`products/${PRODUCT.id}/messages/${parentMessageId}`);
      
      await parentDocRef.set(parentMessageData);

      // Execute function
      await onProductReplyCreated(snap, context);

      // Assertions
      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_A.fcmTokens));
      expect(callArgs.notification.title).toBe('Reply');
      expect(callArgs.notification.body).toBe(`${USER_B.displayName} replied to your message`);
      expect(callArgs.data.type).toBe('reply');
      expect(callArgs.data.productId).toBe(PRODUCT.id);
      expect(callArgs.data.parentMessageId).toBe(parentMessageId);
      expect(callArgs.data.messageId).toBe(replyMessageId);
    });

    it('should NOT send push when parent message does not exist', async () => {
      const { onProductReplyCreated } = require('../functions/index.js');

      const replyMessageData = {
        senderId: USER_B.uid,
        senderName: USER_B.displayName,
        message: 'Reply to deleted message',
        parentId: 'nonexistent_parent'
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        replyMessageData,
        `products/${PRODUCT.id}/messages/msg_123`
      );

      const context = {
        params: {
          productId: PRODUCT.id,
          messageId: 'msg_123'
        }
      };

      await onProductReplyCreated(snap, context);

      // Should not call sendMulticast
      expect(sendMulticastStub).not.toHaveBeenCalled();
    });

    it('should NOT send push when reply sender is parent message sender', async () => {
      const { onProductReplyCreated } = require('../functions/index.js');

      const parentMessageId = 'msg_parent_789';
      
      // Same user sends reply to their own message
      const replyMessageData = {
        senderId: USER_A.uid, // Same as parent sender
        senderName: USER_A.displayName,
        message: 'Self reply',
        parentId: parentMessageId
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        replyMessageData,
        `products/${PRODUCT.id}/messages/msg_123`
      );

      const context = {
        params: {
          productId: PRODUCT.id,
          messageId: 'msg_123'
        }
      };

      // Set parent message
      const parentDocRef = admin.firestore()
        .doc(`products/${PRODUCT.id}/messages/${parentMessageId}`);
      
      await parentDocRef.set({
        senderId: USER_A.uid, // Same sender
        senderName: USER_A.displayName,
        message: 'Original'
      });

      await onProductReplyCreated(snap, context);

      // Should not call sendMulticast (sender == parent sender)
      expect(sendMulticastStub).not.toHaveBeenCalled();
    });
  });

  describe('onProductMessageCreated', () => {
    it('should send push to seller when buyer sends message', async () => {
      const { onProductMessageCreated } = require('../functions/index.js');

      const messageData = {
        senderId: USER_B.uid, // Buyer
        senderName: USER_B.displayName,
        message: 'Is this still available?'
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        messageData,
        `products/${PRODUCT.id}/messages/msg_456`
      );

      const context = {
        params: {
          productId: PRODUCT.id,
          messageId: 'msg_456'
        }
      };

      // Set product document
      const productDocRef = admin.firestore()
        .doc(`products/${PRODUCT.id}`);
      
      await productDocRef.set({
        sellerId: USER_A.uid,
        title: PRODUCT.title
      });

      await onProductMessageCreated(snap, context);

      // Assertions
      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_A.fcmTokens));
      expect(callArgs.notification.title).toBe('Product message');
      expect(callArgs.data.type).toBe('product_message');
      expect(callArgs.data.productId).toBe(PRODUCT.id);
    });

    it('should NOT send push when seller sends message to themselves', async () => {
      const { onProductMessageCreated } = require('../functions/index.js');

      const messageData = {
        senderId: USER_A.uid, // Seller sending to themselves
        senderName: USER_A.displayName,
        message: 'Test'
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        messageData,
        `products/${PRODUCT.id}/messages/msg_789`
      );

      const context = {
        params: {
          productId: PRODUCT.id,
          messageId: 'msg_789'
        }
      };

      // Set product document
      const productDocRef = admin.firestore()
        .doc(`products/${PRODUCT.id}`);
      
      await productDocRef.set({
        sellerId: USER_A.uid,
        title: PRODUCT.title
      });

      await onProductMessageCreated(snap, context);

      // Should not call sendMulticast (seller == sender)
      expect(sendMulticastStub).not.toHaveBeenCalled();
    });
  });

  describe('onPostLikeCreated', () => {
    it('should send push to post owner when someone likes', async () => {
      const { onPostLikeCreated } = require('../functions/index.js');

      const likeData = {
        userId: USER_B.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        likeData,
        `posts/${POST.id}/likes/like_123`
      );

      const context = {
        params: {
          postId: POST.id,
          likeId: 'like_123'
        }
      };

      // Set post document
      const postDocRef = admin.firestore().doc(`posts/${POST.id}`);
      await postDocRef.set({
        userId: USER_A.uid,
        content: POST.content
      });

      await onPostLikeCreated(snap, context);

      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_A.fcmTokens));
      expect(callArgs.notification.title).toBe('New like');
      expect(callArgs.data.type).toBe('like');
      expect(callArgs.data.postId).toBe(POST.id);
    });
  });

  describe('onPostCommentCreated', () => {
    it('should send push to post owner when someone comments', async () => {
      const { onPostCommentCreated } = require('../functions/index.js');

      const commentData = {
        userId: USER_B.uid,
        userName: USER_B.displayName,
        text: 'Nice post!',
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        commentData,
        `posts/${POST.id}/comments/comment_123`
      );

      const context = {
        params: {
          postId: POST.id,
          commentId: 'comment_123'
        }
      };

      // Set post document
      const postDocRef = admin.firestore().doc(`posts/${POST.id}`);
      await postDocRef.set({
        userId: USER_A.uid,
        content: POST.content
      });

      await onPostCommentCreated(snap, context);

      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_A.fcmTokens));
      expect(callArgs.notification.title).toBe('New comment');
      expect(callArgs.data.type).toBe('comment');
      expect(callArgs.data.postId).toBe(POST.id);
      expect(callArgs.data.commentId).toBe('comment_123');
    });
  });

  describe('onTaskVolunteerCreated', () => {
    it('should send push to task owner when someone volunteers', async () => {
      const { onTaskVolunteerCreated } = require('../functions/index.js');

      const volunteerData = {
        volunteerId: USER_B.uid,
        volunteerName: USER_B.displayName,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };

      const snap = testEnv.firestore.makeDocumentSnapshot(
        volunteerData,
        `tasks/task_123/volunteers/vol_456`
      );

      const context = {
        params: {
          taskId: 'task_123',
          volunteerId: 'vol_456'
        }
      };

      // Set task document
      const taskDocRef = admin.firestore().doc('tasks/task_123');
      await taskDocRef.set({
        requesterId: USER_A.uid,
        title: 'Test Task'
      });

      await onTaskVolunteerCreated(snap, context);

      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_A.fcmTokens));
      expect(callArgs.notification.title).toBe('New volunteer');
      expect(callArgs.data.type).toBe('task_volunteer');
    });
  });

  describe('onVolunteerAccepted', () => {
    it('should send push when volunteer status changes to accepted', async () => {
      const { onVolunteerAccepted } = require('../functions/index.js');

      const beforeData = {
        volunteerId: USER_B.uid,
        status: 'pending'
      };

      const afterData = {
        volunteerId: USER_B.uid,
        status: 'accepted'
      };

      const change = {
        before: { data: () => beforeData },
        after: { data: () => afterData }
      };

      const context = {
        params: {
          taskId: 'task_123',
          volunteerDocId: 'vol_789'
        }
      };

      // Set task document
      const taskDocRef = admin.firestore().doc('tasks/task_123');
      await taskDocRef.set({
        requesterId: USER_A.uid,
        title: 'Test Task'
      });

      await onVolunteerAccepted(change, context);

      expect(sendMulticastStub).toHaveBeenCalledTimes(1);
      
      const callArgs = sendMulticastStub.mock.calls[0][0];
      expect(callArgs.tokens).toEqual(expect.arrayContaining(USER_B.fcmTokens));
      expect(callArgs.notification.title).toBe('Volunteer accepted');
      expect(callArgs.data.type).toBe('volunteer_accepted');
    });

    it('should NOT send push if status was already accepted', async () => {
      const { onVolunteerAccepted } = require('../functions/index.js');

      const beforeData = {
        volunteerId: USER_B.uid,
        status: 'accepted' // Already accepted
      };

      const afterData = {
        volunteerId: USER_B.uid,
        status: 'accepted'
      };

      const change = {
        before: { data: () => beforeData },
        after: { data: () => afterData }
      };

      const context = {
        params: {
          taskId: 'task_123',
          volunteerDocId: 'vol_789'
        }
      };

      await onVolunteerAccepted(change, context);

      // Should not call sendMulticast
      expect(sendMulticastStub).not.toHaveBeenCalled();
    });
  });
});
